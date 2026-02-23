import struct
import sys
import os

MEM_PAGE_SIZE = 2048

def unpack_hpf(hpf_path, output_dir=None):
    if not os.path.exists(hpf_path):
        print(f"Error: File not found: {hpf_path}")
        return

    if output_dir is None:
        output_dir = os.path.splitext(hpf_path)[0] + "_extracted"

    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    with open(hpf_path, "rb") as f:
        # Read number of files (uint32 LE)
        num_files_data = f.read(4)
        if len(num_files_data) < 4:
            print("Error: Invalid HPF file (too short)")
            return
        
        num_files = struct.unpack("<I", num_files_data)[0]
        print(f"Found {num_files} files in archive.")

        entries = []
        
        # Read file entries
        for i in range(num_files):
            # HPF Entry Structure (22 bytes)
            # char name[12];
            # uint32 offset;
            # uint16 size;
            # uint16 currentPos;
            # uint16 status;
            
            entry_data = f.read(22)
            if len(entry_data) < 22:
                print(f"Error: Unexpected end of file reading entry {i}")
                break

            name_bytes = entry_data[:12]
            offset = struct.unpack("<I", entry_data[12:16])[0]
            size = struct.unpack("<H", entry_data[16:18])[0]
            current_pos = struct.unpack("<H", entry_data[18:20])[0]
            status = struct.unpack("<H", entry_data[20:22])[0]

            try:
                name = name_bytes.decode('ascii').strip('\x00')
            except UnicodeDecodeError:
                name = f"FILE_{i}.DAT"
                print(f"Warning: Could not decode name for file {i}, using {name}")

            entries.append({
                'name': name,
                'offset': offset,
                'size': size
            })

        # Extract files
        for i, entry in enumerate(entries):
            file_offset = entry['offset'] * MEM_PAGE_SIZE
            file_size = entry['size'] * MEM_PAGE_SIZE
            file_name = entry['name']
            
            print(f"Extracting {file_name} (Offset: {file_offset}, Size: {file_size})...")

            f.seek(file_offset)
            data = f.read(file_size)
            
            if len(data) != file_size:
                print(f"Warning: Unexpected end of file reading {file_name}. Expected {file_size}, got {len(data)}")

            out_path = os.path.join(output_dir, file_name)
            with open(out_path, "wb") as out_f:
                out_f.write(data)

    print(f"Done. Extracted {len(entries)} files to {output_dir}")

def list_hpf(hpf_path):
    if not os.path.exists(hpf_path):
        print(f"Error: File not found: {hpf_path}")
        return

    with open(hpf_path, "rb") as f:
        num_files_data = f.read(4)
        if len(num_files_data) < 4:
            print("Error: Invalid HPF file")
            return
        
        num_files = struct.unpack("<I", num_files_data)[0]
        print(f"Listing {num_files} files from {hpf_path}:")
        print(f"{'Name':<15} {'Offset (sectors)':<10} {'Size (sectors)':<10} {'Size (bytes)':<10}")
        print("-" * 50)

        for i in range(num_files):
            entry_data = f.read(22)
            if len(entry_data) < 22:
                break

            name_bytes = entry_data[:12]
            offset = struct.unpack("<I", entry_data[12:16])[0]
            size = struct.unpack("<H", entry_data[16:18])[0]
            
            try:
                name = name_bytes.decode('ascii').strip('\x00')
            except:
                name = "???"

            print(f"{name:<15} {offset:<10} {size:<10} {size * MEM_PAGE_SIZE:<10}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python hpf_unpack.py <hpf_file> [output_dir] or python hpf_unpack.py list <hpf_file>")
        sys.exit(1)

    if sys.argv[1] == "list":
         if len(sys.argv) < 3:
             print("Usage: python hpf_unpack.py list <hpf_file>")
             sys.exit(1)
         list_hpf(sys.argv[2])
    else:
        hpf_file = sys.argv[1]
        out_dir = sys.argv[2] if len(sys.argv) > 2 else None
        unpack_hpf(hpf_file, out_dir)
