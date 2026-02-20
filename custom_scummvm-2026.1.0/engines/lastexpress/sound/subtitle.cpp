/* ScummVM - Graphic Adventure Engine
 *
 * ScummVM is the legal property of its developers, whose names
 * are too numerous to list here. Please refer to the COPYRIGHT
 * file distributed with this source distribution.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#include "lastexpress/sound/subtitle.h"
#include "lastexpress/sound/sound.h"
#include "lastexpress/data/archive.h"

#include "lastexpress/helpers.h"
#include "lastexpress/lastexpress.h"

#include "common/archive.h"
#include "common/config-manager.h"
#include "common/array.h"
#include "common/file.h"
#include "common/memstream.h"
#include "common/str-enc.h"
#include "graphics/font.h"
#include "graphics/fontman.h"
#ifdef USE_FREETYPE2
#include "graphics/fonts/ttf.h"
#endif
#include "subtitle.h"
#include <cstdlib>

namespace LastExpress {

namespace {

static const int kSubtitleAreaLeft = 80;
static const int kSubtitleAreaTop = 420;
static const int kSubtitleAreaWidth = 480;
static const int kSubtitleAreaDefaultHeight = 38;
static const int kSubtitleAreaLocalizedHeight = 48;

static int getLocalizedSubtitleFontSizeFromConfig() {
	const int kDefaultSize = 14;
	const int kMinSize = 8;
	const int kMaxSize = 48;
	static const char *const kConfigKey = "lastexpress_kor_font_size";

	int size = kDefaultSize;
	if (ConfMan.hasKey(kConfigKey)) {
		size = ConfMan.getInt(kConfigKey);
		if (size < kMinSize)
			size = kMinSize;
		else if (size > kMaxSize)
			size = kMaxSize;
	}

	return size;
}

Common::String decodeSubtitleEscapes(const Common::String &input) {
	Common::String output;

	bool escaped = false;
	for (Common::String::const_iterator it = input.begin(); it != input.end(); ++it) {
		char c = *it;
		if (!escaped) {
			if (c == '\\') {
				escaped = true;
			} else {
				output += c;
			}
			continue;
		}

		switch (c) {
		case 'n':
			output += '\n';
			break;
		case 'r':
			output += '\r';
			break;
		case 't':
			output += '\t';
			break;
		case '\\':
			output += '\\';
			break;
		default:
			output += '\\';
			output += c;
			break;
		}

		escaped = false;
	}

	if (escaped)
		output += '\\';

	return output;
}

Common::String makeSubtitleLookupKey(const char *filename, int32 subtitleIndex) {
	return Common::String::format("%s|%d", filename, subtitleIndex);
}

Common::SeekableReadStream *createReadStreamFromKoreanOverlay(LastExpressEngine *engine, const char *filename) {
	HPF *archive = engine->getArchiveManager()->openHPF(filename);
	if (!archive)
		return nullptr;

	const uint32 byteSize = archive->size * MEM_PAGE_SIZE;
	byte *buffer = (byte *)malloc(byteSize);
	if (!buffer) {
		engine->getArchiveManager()->closeHPF(archive);
		warning("SubtitleManager: out of memory while loading '%s' from overlay archive", filename);
		return nullptr;
	}

	engine->getArchiveManager()->readHPF(archive, buffer, archive->size);
	engine->getArchiveManager()->closeHPF(archive);

	uint32 effectiveSize = byteSize;
	while (effectiveSize && buffer[effectiveSize - 1] == 0)
		--effectiveSize;

	return new Common::MemoryReadStream(buffer, effectiveSize, DisposeAfterUse::YES);
}

} // End of anonymous namespace

Subtitle::Subtitle(LastExpressEngine *engine, const char *filename, Slot *slot) {
	_engine = engine;

	memset(_filename, 0, sizeof(_filename));
	_slot = slot;

	if (_engine->getSubtitleManager()->_subtitlesQueue) {
		Subtitle *i;
		for (i = _engine->getSubtitleManager()->_subtitlesQueue; i->_next; i = i->_next);

		i->_next = this;
	} else {
		_engine->getSubtitleManager()->_subtitlesQueue = this;
	}

	// Original bug: the _filename was 12 chars long, but sometimes
	// the sound files are a couple of characters longer. This would trigger
	// a truncated string warning within sprintf_s; we have raised the size
	// to be able to make it work like the original did (since it used plain sprintf).
	Common::sprintf_s(_filename, sizeof(_filename), "%s.SBE", filename);

	HPF *archive = _engine->getArchiveManager()->openHPF(_filename);
	if (archive) {
		_engine->getArchiveManager()->closeHPF(archive);

		if ((_engine->getSubtitleManager()->_flags & kSubFlagLoaded) == 0) {
			load();
		}
	} else {
		_status = kSubFlagStatusKilled;
	}
}

Subtitle::~Subtitle() {
	if (_engine->getSubtitleManager()->_subtitlesQueue) {
		if (_engine->getSubtitleManager()->_subtitlesQueue == this) {
			_engine->getSubtitleManager()->_subtitlesQueue = _engine->getSubtitleManager()->_subtitlesQueue->_next;
		} else {
			Subtitle *next;
			Subtitle *queue = _engine->getSubtitleManager()->_subtitlesQueue;

			if (_engine->getSubtitleManager()->_subtitlesQueue->_next == this) {
				queue->_next = _next;
			} else {
				do {
					next = queue->_next;
					if (!next)
						break;

					queue = queue->_next;
				} while (next->_next != this);

				if (queue->_next == this)
					queue->_next = _next;
			}

		}
	}

	if (_engine->getSubtitleManager()->_currentSubtitle == this) {
		if (!_engine->shouldQuit())
			_engine->getSubtitleManager()->clearSubArea();

		_engine->getSubtitleManager()->_currentSubtitle = nullptr;
		_engine->getSubtitleManager()->_flags = 0;
	}
}

void Subtitle::load() {
	HPF *archive;

	archive = _engine->getArchiveManager()->openHPF(_filename);
	_data = _engine->getSubtitleManager()->_subtitlesData + 1;
	_engine->getSubtitleManager()->_subtitleIndex = -1;

	if (archive) {
		_engine->getArchiveManager()->readHPF(archive, _engine->getSubtitleManager()->_subtitlesData, archive->size);
		_engine->getArchiveManager()->closeHPF(archive);

		for (int i = 0; i < (archive->size * MEM_PAGE_SIZE) / 2; i++) {
			_engine->getSubtitleManager()->_subtitlesData[i] = READ_LE_UINT16(&_engine->getSubtitleManager()->_subtitlesData[i]);
		}

		if (_engine->getSubtitleManager()->_subtitlesData[0]) {
			for (int i = 0; i < _engine->getSubtitleManager()->_subtitlesData[0]; i++) {
				if (!_data[1])
					_data[1] = _data[_data[3] + 4 + _data[2]];

				_data += _data[3] + _data[2] + 4;
			}
		}

		_engine->getSubtitleManager()->_flags |= kSubFlagLoaded;
		_engine->getSubtitleManager()->_currentSubtitle = this;
	}
}

void Subtitle::update() {
	int32 count = 0;

	_data = _engine->getSubtitleManager()->_subtitlesData + 1;

	if (_data[1] <= _slot->getTime()) {
		do {
			if (_engine->getSubtitleManager()->_subtitlesData[0] <= count)
				break;

			count++;
			_data = &_data[_data[3] + 4 + _data[2]];
		} while (_data[1] <= _slot->getTime());
	}

	if (_engine->getSubtitleManager()->_subtitlesData[0] <= count) {
		_status = kSubFlagStatusKilled;

		if ((_engine->getSubtitleManager()->_flags & kSubFlagDrawOnScreen) != 0)
			_engine->getSubtitleManager()->clearSubArea();
	} else {
		if (_data[0] > _slot->getTime() || _data[1] <= _slot->getTime()) {
			if ((_engine->getSubtitleManager()->_flags & kSubFlagDrawOnScreen) != 0) {
				_engine->getSubtitleManager()->clearSubArea();
				_engine->getSubtitleManager()->_currentSubtitle = this;

				return;
			}
		} else if (count != _engine->getSubtitleManager()->_subtitleIndex) {
			_engine->getSubtitleManager()->_currentSubtitle = this;
			_engine->getSubtitleManager()->drawSubArea(&_data[2], count);
			_engine->getSubtitleManager()->_subtitleIndex = count;
			_engine->getSubtitleManager()->_currentSubtitle = this;

			return;
		}
	}

	_engine->getSubtitleManager()->_currentSubtitle = this;
}

void Subtitle::kill() {
	_status = kSubFlagStatusKilled;
}

SubtitleManager::SubtitleManager(LastExpressEngine *engine) {
	_engine = engine;

	memset(_upperLineCharWidths, 0, sizeof(_upperLineCharWidths));
	memset(_lowerLineCharWidths, 0, sizeof(_lowerLineCharWidths));
	memset(_upperLineChars, 0, sizeof(_upperLineChars));
	memset(_lowerLineChars, 0, sizeof(_lowerLineChars));
}

SubtitleManager::~SubtitleManager() {
	if (_localizedSubtitleFontOwned) {
		delete _localizedSubtitleFont;
		_localizedSubtitleFont = nullptr;
		_localizedSubtitleFontOwned = false;
	}

	SAFE_DELETE(_font);
}

void SubtitleManager::initSubtitles() {
	HPF *archive = _engine->getArchiveManager()->openHPF("FONT.DAT");

	if (archive) {
		if (_font->fontData) {
			free(_font->fontData);
			_font->fontData = nullptr;
		}

		byte *fontData = (byte *)malloc(MEM_PAGE_SIZE * archive->size);

		if (fontData) {
			_engine->getArchiveManager()->readHPF(archive, fontData, archive->size);
			_engine->getArchiveManager()->closeHPF(archive);

			Common::MemoryReadStream *fontStream = new Common::MemoryReadStream(fontData, MEM_PAGE_SIZE * archive->size, DisposeAfterUse::YES);

			for (int i = 0; i < 16; i++) {
				_font->palette[i] = fontStream->readUint16LE();
			}

			for (int i = 0; i < 256; i++) {
				_font->charMap[i] = fontStream->readByte();
			}

			for (int i = 0; i < 256; i++) {
				_font->charKerning[i] = fontStream->readByte();
			}

			uint32 sizeOfData = MEM_PAGE_SIZE * archive->size - (16 * sizeof(uint16) + 256 + 256);
			_font->fontData = (byte *)malloc(sizeOfData);

			assert(_font->fontData);

			for (uint i = 0; !fontStream->eos() && i < sizeOfData; i++) {
				_font->fontData[i] = fontStream->readByte();
			}

			delete fontStream;
		} else {
			_font->fontData = nullptr;
		}
	} else {
		_font->fontData = nullptr;
	}

	_engine->getGraphicsManager()->modifyPalette(_font->palette, 16);
	initLocalizedSubtitlesSupport();
}

void SubtitleManager::clearLocalizedSubtitleRenderState() {
	_useLocalizedSubtitleLine = false;
	_localizedUpperLine.clear();
	_localizedLowerLine.clear();
	_localizedUpperLineWidth = 0;
	_localizedLowerLineWidth = 0;
}

int SubtitleManager::getRequestedSubtitleAreaHeight() const {
	return (_useLocalizedSubtitleLine && _localizedSubtitleFont) ? kSubtitleAreaLocalizedHeight : kSubtitleAreaDefaultHeight;
}

void SubtitleManager::initLocalizedSubtitlesSupport() {
	if (_localizedSupportInitialized)
		return;

	_localizedSupportInitialized = true;
	_localizedSubtitlesAvailable = false;
	_localizedSubtitleLines.clear();
	clearLocalizedSubtitleRenderState();

	static const char *const kLocalizedSubtitleTableNames[] = {
		"SUBKO.TSV",
		"subko.tsv"
	};

	Common::File subtitleTableFile;
	Common::SeekableReadStream *subtitleTableStream = nullptr;
	bool subtitleTableFromOverlay = false;
	const char *loadedTableName = nullptr;
	auto releaseSubtitleTableStream = [&]() {
		if (subtitleTableStream && subtitleTableStream != &subtitleTableFile)
			delete subtitleTableStream;
		subtitleTableStream = nullptr;
	};

	for (uint i = 0; i < ARRAYSIZE(kLocalizedSubtitleTableNames); ++i) {
		if (subtitleTableFile.open(kLocalizedSubtitleTableNames[i])) {
			subtitleTableStream = &subtitleTableFile;
			loadedTableName = kLocalizedSubtitleTableNames[i];
			break;
		}

		subtitleTableStream = createReadStreamFromKoreanOverlay(_engine, kLocalizedSubtitleTableNames[i]);
		if (subtitleTableStream) {
			loadedTableName = kLocalizedSubtitleTableNames[i];
			subtitleTableFromOverlay = true;
			break;
		}
	}

	if (!loadedTableName)
		return;

	int32 parsedLines = 0;
	int32 lineNumber = 0;
	while (!subtitleTableStream->eos()) {
		Common::String line = subtitleTableStream->readLine();
		++lineNumber;

		if (lineNumber == 1 && line.size() >= 3 &&
			static_cast<byte>(line[0]) == 0xEF &&
			static_cast<byte>(line[1]) == 0xBB &&
			static_cast<byte>(line[2]) == 0xBF) {
			line.erase(0, 3);
		}

		line.trim();
		if (line.empty() || line.hasPrefix("#") || line.hasPrefix(";"))
			continue;

		uint32 firstSeparator = line.find('|');
		if (firstSeparator == Common::String::npos)
			firstSeparator = line.find('\t');

		if (firstSeparator == Common::String::npos) {
			warning("SubtitleManager: invalid localized subtitle row at line %d: missing delimiter", lineNumber);
			continue;
		}

		const char delimiter = line[firstSeparator];
		const uint32 secondSeparator = line.find(delimiter, firstSeparator + 1);
		if (secondSeparator == Common::String::npos) {
			warning("SubtitleManager: invalid localized subtitle row at line %d: missing second delimiter", lineNumber);
			continue;
		}

		Common::String subtitleName = line.substr(0, firstSeparator);
		Common::String subtitleIndexText = line.substr(firstSeparator + 1, secondSeparator - firstSeparator - 1);
		Common::String subtitleText = line.substr(secondSeparator + 1);

		subtitleName.trim();
		subtitleIndexText.trim();

		if (subtitleName.empty() || subtitleIndexText.empty()) {
			warning("SubtitleManager: invalid localized subtitle row at line %d: empty name or index", lineNumber);
			continue;
		}

		char *indexEnd = nullptr;
		const long subtitleIndex = strtol(subtitleIndexText.c_str(), &indexEnd, 10);
		if (indexEnd == subtitleIndexText.c_str() || *indexEnd != '\0' ||
			subtitleIndex < 0 || subtitleIndex > 0x7FFFFFFF) {
			warning("SubtitleManager: invalid localized subtitle row at line %d: bad index '%s'", lineNumber, subtitleIndexText.c_str());
			continue;
		}

		if (!subtitleName.hasSuffixIgnoreCase(".SBE"))
			subtitleName += ".SBE";

		Common::U32String subtitleTextU32 = Common::convertUtf8ToUtf32(decodeSubtitleEscapes(subtitleText));
		_localizedSubtitleLines.setVal(makeSubtitleLookupKey(subtitleName.c_str(), (int32)subtitleIndex), subtitleTextU32);
		++parsedLines;
	}

	if (!parsedLines) {
		warning("SubtitleManager: localized subtitle table '%s' had no valid rows", loadedTableName);
		releaseSubtitleTableStream();
		return;
	}

	releaseSubtitleTableStream();

	if (_localizedSubtitleFontOwned && _localizedSubtitleFont) {
		delete _localizedSubtitleFont;
		_localizedSubtitleFont = nullptr;
		_localizedSubtitleFontOwned = false;
	}

#ifdef USE_FREETYPE2
	const int localizedFontSize = getLocalizedSubtitleFontSizeFromConfig();
	static const char *const kLocalizedFontNames[] = {
		"Korean.TTF",
		"KOREAN.TTF"
	};

	for (uint i = 0; i < ARRAYSIZE(kLocalizedFontNames) && !_localizedSubtitleFont; ++i) {
		bool fontFromOverlay = false;
		Common::SeekableReadStream *fontStream = SearchMan.createReadStreamForMember(kLocalizedFontNames[i]);
		if (!fontStream) {
			fontStream = createReadStreamFromKoreanOverlay(_engine, kLocalizedFontNames[i]);
			fontFromOverlay = (fontStream != nullptr);
		}

		if (!fontStream)
			continue;

		_localizedSubtitleFont = Graphics::loadTTFFont(
			fontStream,
			DisposeAfterUse::YES,
			localizedFontSize,
			Graphics::kTTFSizeModeCharacter,
			0,
			0,
			Graphics::kTTFRenderModeLight
		);

		if (_localizedSubtitleFont) {
			_localizedSubtitleFontOwned = true;
			debug(2, "SubtitleManager: localized subtitle font loaded from '%s'%s (size=%d)",
				kLocalizedFontNames[i], fontFromOverlay ? " via KOREAN.HPF" : "", localizedFontSize);
		}
	}
#endif

	if (!_localizedSubtitleFont)
		_localizedSubtitleFont = FontMan.getFontByUsage(Graphics::FontManager::kLocalizedFont);
	if (!_localizedSubtitleFont)
		_localizedSubtitleFont = FontMan.getFontByUsage(Graphics::FontManager::kGUIFont);
	if (!_localizedSubtitleFont)
		_localizedSubtitleFont = FontMan.getFontByUsage(Graphics::FontManager::kBigGUIFont);

	if (!_localizedSubtitleFont) {
		warning("SubtitleManager: localized subtitle table found, but no drawable font is available");
		_localizedSubtitleLines.clear();
		return;
	}

	_localizedSubtitlesAvailable = true;
	debug(2, "SubtitleManager: loaded %d localized subtitle rows from '%s'%s",
		parsedLines, loadedTableName, subtitleTableFromOverlay ? " via KOREAN.HPF" : "");
}

bool SubtitleManager::setupLocalizedSubtitleLines(int32 subtitleIndex) {
	clearLocalizedSubtitleRenderState();

	if (!_localizedSubtitlesAvailable || !_localizedSubtitleFont || !_currentSubtitle)
		return false;

	Common::U32String localizedText;
	if (!_localizedSubtitleLines.tryGetVal(makeSubtitleLookupKey(_currentSubtitle->_filename, subtitleIndex), localizedText))
		return false;

	Common::Array<Common::U32String> wrappedLines;
	_localizedSubtitleFont->wordWrapText(localizedText, 456, wrappedLines, 0, Graphics::kWordWrapOnExplicitNewLines);
	if (wrappedLines.empty())
		return false;

	_localizedUpperLine = wrappedLines[0];
	if (wrappedLines.size() > 1)
		_localizedLowerLine = wrappedLines[1];

	_localizedUpperLineWidth = _localizedSubtitleFont->getStringWidth(_localizedUpperLine);
	_localizedLowerLineWidth = _localizedSubtitleFont->getStringWidth(_localizedLowerLine);
	_useLocalizedSubtitleLine = true;

	return true;
}

void SubtitleManager::storeVArea(PixMap *pixels) {
	if (_engine->getGraphicsManager()->acquireSurface()) {
		PixMap *screenSurface = (PixMap *)((byte *)_engine->getGraphicsManager()->_screenSurface.getPixels() + ((kSubtitleAreaTop * 640 + kSubtitleAreaLeft) * sizeof(PixMap)));

		for (int i = _activeSubtitleAreaHeight; i > 0; i--) {
			for (int j = kSubtitleAreaWidth; j > 0; j--) {
				*pixels++ = *screenSurface++;
			}

			screenSurface += 640 - kSubtitleAreaWidth;
		}

		_engine->getGraphicsManager()->unlockSurface();
	}
}

void SubtitleManager::restoreVArea(PixMap *pixels) {
	if (_engine->getGraphicsManager()->acquireSurface()) {
		PixMap *screenSurface = (PixMap *)((byte *)_engine->getGraphicsManager()->_screenSurface.getPixels() + ((kSubtitleAreaTop * 640 + kSubtitleAreaLeft) * sizeof(PixMap)));

		for (int i = _activeSubtitleAreaHeight; i > 0; i--) {
			for (int j = kSubtitleAreaWidth; j > 0; j--) {
				*screenSurface++ = *pixels++;
			}

			screenSurface += 640 - kSubtitleAreaWidth;
		}

		_engine->getGraphicsManager()->unlockSurface();
	}
}

void SubtitleManager::vSubOn() {
	_activeSubtitleAreaHeight = getRequestedSubtitleAreaHeight();
	storeVArea(_engine->getGraphicsManager()->_subtitlesBackBuffer);

	if (_useLocalizedSubtitleLine && _localizedSubtitleFont) {
		if (_engine->getGraphicsManager()->acquireSurface()) {
			Graphics::Surface *screenSurface = &_engine->getGraphicsManager()->_screenSurface;
			const Graphics::PixelFormat &format = screenSurface->format;
			const uint32 textColor = format.RGBToColor(255, 255, 255);
			const uint32 shadowColor = format.RGBToColor(0, 0, 0);

			int lineCount = _localizedLowerLine.empty() ? 1 : 2;
			int fontHeight = _localizedSubtitleFont->getFontHeight();
			if (fontHeight <= 0)
				fontHeight = 16;

			const int subtitleAreaTop = kSubtitleAreaTop;
			const int subtitleAreaHeight = _activeSubtitleAreaHeight;
			const int shadowOffset = 1;
			int lineSpacing = 2;
			if (lineCount > 1) {
				const int maxLineSpacing = (subtitleAreaHeight - lineCount * fontHeight - shadowOffset) / (lineCount - 1);
				if (maxLineSpacing < 0)
					lineSpacing = 0;
				else if (lineSpacing > maxLineSpacing)
					lineSpacing = maxLineSpacing;
			}
			const int blockHeight = lineCount * fontHeight + (lineCount - 1) * lineSpacing + shadowOffset;
			int lineY = subtitleAreaTop + (subtitleAreaHeight - blockHeight) / 2;
			if (lineY < subtitleAreaTop)
				lineY = subtitleAreaTop;

			if (!_localizedUpperLine.empty()) {
				int upperLineX = kSubtitleAreaLeft + (kSubtitleAreaWidth - _localizedUpperLineWidth) / 2;
				if (upperLineX < kSubtitleAreaLeft)
					upperLineX = kSubtitleAreaLeft;

				_localizedSubtitleFont->drawString(screenSurface, _localizedUpperLine, upperLineX + 1, lineY + 1, kSubtitleAreaWidth, shadowColor);
				_localizedSubtitleFont->drawString(screenSurface, _localizedUpperLine, upperLineX, lineY, kSubtitleAreaWidth, textColor);
			}

			if (!_localizedLowerLine.empty()) {
				const int lowerLineY = lineY + fontHeight + lineSpacing;
				int lowerLineX = kSubtitleAreaLeft + (kSubtitleAreaWidth - _localizedLowerLineWidth) / 2;
				if (lowerLineX < kSubtitleAreaLeft)
					lowerLineX = kSubtitleAreaLeft;

				_localizedSubtitleFont->drawString(screenSurface, _localizedLowerLine, lowerLineX + 1, lowerLineY + 1, kSubtitleAreaWidth, shadowColor);
				_localizedSubtitleFont->drawString(screenSurface, _localizedLowerLine, lowerLineX, lowerLineY, kSubtitleAreaWidth, textColor);
			}

			_engine->getGraphicsManager()->unlockSurface();
		}

		return;
	}

	if (_font->fontData[0] && _engine->getGraphicsManager()->acquireSurface()) {
		PixMap *surfaceLine1 = (PixMap *)((byte *)_engine->getGraphicsManager()->_screenSurface.getPixels() + ((640 - _upperLineXStart) & ~1) + 537600);
		for (int i = 0; i < _upperLineLength; ++i) {
			drawChar(surfaceLine1, _upperLineChars[i]);
			surfaceLine1 += _upperLineCharWidths[i];
		}

		PixMap *surfaceLine2 = (PixMap *)((byte *)_engine->getGraphicsManager()->_screenSurface.getPixels() + ((640 - _lowerLineXStart) & ~1) + 563200);
		for (int i = 0; i < _lowerLineLength; ++i) {
			drawChar(surfaceLine2, _lowerLineChars[i]);
			surfaceLine2 += _lowerLineCharWidths[i];
		}

		_engine->getGraphicsManager()->unlockSurface();
	}
}

void SubtitleManager::vSubOff() {
	restoreVArea(_engine->getGraphicsManager()->_subtitlesBackBuffer);
}

void SubtitleManager::clearSubArea() {
	const int subtitleAreaHeight = _activeSubtitleAreaHeight;
	_flags &= ~kSubFlagDrawOnScreen;
	clearLocalizedSubtitleRenderState();
	_engine->getGraphicsManager()->burstBox(kSubtitleAreaLeft, kSubtitleAreaTop, kSubtitleAreaWidth, subtitleAreaHeight);
	_activeSubtitleAreaHeight = kSubtitleAreaDefaultHeight;
}

void SubtitleManager::drawChar(PixMap *destBuf, uint8 whichChar) {
	byte *fontPtr = &_font->fontData[(288 * _font->charMap[whichChar] >> 1) + 2];

	for (int row = 0; row < 18; row++) {
		for (int col = 0; col < 8; col++) {
			uint8 pixelByte = *fontPtr;

			uint8 upperNibble = pixelByte >> 4;
			if (upperNibble != 0) {
				*destBuf = _font->palette[upperNibble];
			}

			destBuf++;

			uint8 lowerNibble = pixelByte & 0x0F;
			if (lowerNibble != 0) {
				*destBuf = _font->palette[lowerNibble];
			}

			destBuf++;

			fontPtr++;
		}

		destBuf += 624;
	}
}

void SubtitleManager::drawSubArea(uint16 *subtitleData, int32 subtitleIndex) {
	if (setupLocalizedSubtitleLines(subtitleIndex)) {
		_activeSubtitleAreaHeight = getRequestedSubtitleAreaHeight();
		_flags |= kSubFlagDrawOnScreen;
		_engine->getGraphicsManager()->burstBox(kSubtitleAreaLeft, kSubtitleAreaTop, kSubtitleAreaWidth, _activeSubtitleAreaHeight);
		return;
	}

	uint16 *data = subtitleData + 2;
	_upperLineLength = subtitleData[0];
	_lowerLineLength = subtitleData[1];

	_upperLineXStart = 0;
	for (int i = 0; i < _upperLineLength; i++) {
		_upperLineChars[i] = *data;
		_upperLineCharWidths[i] = _font->charKerning[_upperLineChars[i]] + 1;
		_upperLineXStart += _font->charKerning[_upperLineChars[i]] + 1;
		data++;
	}

	_lowerLineXStart = 0;
	for (int i = 0; i < _lowerLineLength; i++) {
		_lowerLineChars[i] = *data;
		_lowerLineCharWidths[i] = _font->charKerning[_lowerLineChars[i]] + 1;
		_lowerLineXStart += _font->charKerning[_lowerLineChars[i]] + 1;
		data++;
	}

	_activeSubtitleAreaHeight = kSubtitleAreaDefaultHeight;
	_flags |= kSubFlagDrawOnScreen;
	_engine->getGraphicsManager()->burstBox(kSubtitleAreaLeft, kSubtitleAreaTop, kSubtitleAreaWidth, _activeSubtitleAreaHeight);
}

void SubtitleManager::subThread() {
	int32 maxPriority;
	Subtitle *queueElement;
	Subtitle *selectedSubtitle;
	Slot *slot;
	int32 curPriority;

	maxPriority = 0;
	queueElement = _subtitlesQueue;

	for (selectedSubtitle = 0; queueElement; queueElement = queueElement->_next) {
		slot = queueElement->_slot;

		if ((slot->getStatusFlags() & kSoundFlagPlaying) == 0 ||
			(slot->getStatusFlags() & kSoundFlagMute) != 0 ||
			!slot->getTime() ||
			((slot->getStatusFlags() & kSoundVolumeMask) < kVolume6) ||
			((_engine->getNISManager()->getNISFlag() & kNisFlagSoundFade) != 0 && slot->getPriority() < 90)) {

			curPriority = 0;
		} else {
			curPriority = slot->getPriority() + (slot->getStatusFlags() & kSoundVolumeMask);

			if (_currentSubtitle == queueElement)
				curPriority += 4;
		}

		if (maxPriority < curPriority) {
			maxPriority = curPriority;
			selectedSubtitle = queueElement;
		}
	}

	if (_currentSubtitle == selectedSubtitle) {
		if (selectedSubtitle)
			selectedSubtitle->update();

		return;
	}

	if ((_flags & kSubFlagDrawOnScreen) != 0)
		clearSubArea();

	if (selectedSubtitle) {
		selectedSubtitle->load();

		if (selectedSubtitle)
			selectedSubtitle->update();
	}
}

} // End of namespace LastExpress
