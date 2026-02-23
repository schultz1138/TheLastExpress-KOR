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

#ifndef LASTEXPRESS_SOUND_SUBTITLE_H
#define LASTEXPRESS_SOUND_SUBTITLE_H

#include "common/hashmap.h"
#include "common/hash-str.h"
#include "common/ustr.h"

#include "lastexpress/shared.h"
#include "lastexpress/sound/slot.h"

namespace Graphics {
class Font;
}

namespace LastExpress {

class LastExpressEngine;
class Slot;
struct FontData;

typedef uint16 PixMap;

class Subtitle {
	friend class Slot;
	friend class LastExpressEngine;
	friend class SubtitleManager;

public:
	Subtitle(LastExpressEngine *engine, const char *filename, Slot *slot);
	~Subtitle();
	void load();
	void update();
	void kill();

protected:
	LastExpressEngine *_engine = nullptr;
	char _filename[24]; // Originally 12 bytes, but it constantly overflows...
	int _status = 0;
	Slot *_slot = nullptr;
	uint16 *_data = nullptr;
	Subtitle *_next = nullptr;
};

class SubtitleManager {
	friend class Subtitle;
	friend class MemoryManager;
	friend class GraphicsManager;

public:
	SubtitleManager(LastExpressEngine *engine);
	~SubtitleManager();

	void initSubtitles();
	void storeVArea(PixMap *pixels);
	void restoreVArea(PixMap *pixels);
	void vSubOn();
	void vSubOff();
	void clearSubArea();
	void drawChar(PixMap *destBuf, uint8 whichChar);
	void drawSubArea(uint16 *subtitleData, int32 subtitleIndex);
	void subThread();

private:
	void initLocalizedSubtitlesSupport();
	bool setupLocalizedSubtitleLines(int32 subtitleIndex);
	void clearLocalizedSubtitleRenderState();
	int getRequestedSubtitleAreaHeight() const;

	LastExpressEngine *_engine = nullptr;

	uint16 *_subtitlesData = nullptr;
	Subtitle *_subtitlesQueue = nullptr;
	Subtitle *_currentSubtitle = nullptr;
	int32 _flags = 0;
	int32 _subtitleIndex = 0;
	int32 _lowerLineXStart = 0;
	int32 _upperLineXStart = 0;
	int32 _upperLineCharWidths[60];
	int32 _lowerLineCharWidths[60];
	int16 _upperLineChars[60];
	int16 _lowerLineChars[60];
	int32 _upperLineLength = 0;
	int32 _lowerLineLength = 0;
	FontData *_font = nullptr;

	bool _localizedSupportInitialized = false;
	bool _localizedSubtitlesAvailable = false;
	bool _useLocalizedSubtitleLine = false;
	bool _localizedSubtitleFontOwned = false;
	const Graphics::Font *_localizedSubtitleFont = nullptr;
	Common::U32String _localizedUpperLine;
	Common::U32String _localizedLowerLine;
	int32 _localizedUpperLineWidth = 0;
	int32 _localizedLowerLineWidth = 0;
	int32 _activeSubtitleAreaHeight = 38;
	Common::HashMap<Common::String, Common::U32String, Common::IgnoreCase_Hash, Common::IgnoreCase_EqualTo> _localizedSubtitleLines;
};

} // End of namespace LastExpress

#endif // LASTEXPRESS_SOUND_SUBTITLE_H
