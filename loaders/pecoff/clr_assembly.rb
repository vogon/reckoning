require './exe'
require './helpers'

def popcount(n)
    count = 0

    while n > 0 do
        if (n & 1) != 0 then
            count = count + 1
        end

        n = n >> 1
    end

    count
end

module CLR

class CLIHeader
    class Characteristics < Flags
        enum_attr :il_only,             0x00000001
        enum_attr :requires_32_bit,     0x00000002
        enum_attr :strong_name_signed,  0x00000008
        enum_attr :native_entry_point,  0x00000010
        enum_attr :track_debug_data,    0x00010000
    end

    def CLIHeader.read(f)
        f.extend BinaryIO
        hdr = CLIHeader.new

        hdr.cb = f.read_dword
        hdr.major_runtime_version = f.read_word
        hdr.minor_runtime_version = f.read_word
        hdr.metadata = f.read_rva_size
        hdr.flags = Characteristics.new(f.read_dword)
        hdr.entry_point_token = f.read_dword
        hdr.resources = f.read_rva_size
        hdr.strong_name_signature = f.read_rva_size
        hdr.code_manager_table = f.read_qword
        hdr.vtable_fixups = f.read_rva_size
        hdr.export_address_table_jumps = f.read_qword
        hdr.managed_native_header = f.read_qword

        return hdr
    end

    attr_accessor :cb, :major_runtime_version, :minor_runtime_version,
        :metadata, :flags, :entry_point_token, :resources, 
        :strong_name_signature, :code_manager_table, :vtable_fixups,
        :export_address_table_jumps, :managed_native_header
end

class StreamHeader
    def StreamHeader.read(f)
        f.extend BinaryIO
        hdr = StreamHeader.new

        hdr.offset = f.read_dword
        hdr.size = f.read_dword

        name = ""

        loop do
            block = f.read(4)
            name.concat block

            if block[3] == "\0" then
                break
            end
        end

        hdr.name = name

        return hdr
    end

    attr_accessor :offset, :size, :name
end

class StringsHeap
    def StringsHeap.read(f, len)
        # read whole heap at once
        data = f.read(len)

        # data now contains "ASCII-8BIT" string data.  it's really 
        # NUL-terminated UTF-8. so convert it now.
        data.force_encoding(Encoding::UTF_8)

        StringsHeap.new(data)
    end

    def initialize(data)
        @data = data
    end

    def [](index)
        # read until the next \0.
        @data[index...@data.index("\0", index)]
    end
end

require './clr_mdtable'

class SquiggleStream
    class HeapSizes < Flags
        enum_attr :big_string_heap,     0x01
        enum_attr :big_guid_heap,       0x02
        enum_attr :big_blob_heap,       0x04
    end

    public
    def SquiggleStream.read(f, len)
        f.extend BinaryIO
        stream = SquiggleStream.new

        stream.reserved_0 = f.read_dword
        stream.major_version = f.read_byte
        stream.minor_version = f.read_byte
        stream.heap_sizes = HeapSizes.new(f.read_byte)
        stream.reserved_7 = f.read_byte
        stream.valid = f.read_qword
        stream.sorted = f.read_qword

        stream.rows = []
        popcount(stream.valid.to_i).times do |i|
            stream.rows[i] = f.read_dword
        end

        # grab a list of all the classes which are metadata types, sorted by their table id
        tables_classes = CLR::Tables.constants.
                            map { |const| CLR::Tables.const_get(const) }.
                            select { |klass| klass < CLR::MDRow }.
                            sort { |a, b| a.table_id <=> b.table_id }

        # stream.rows is indexed by the offset of the table into the file, not the actual table id.
        # we need to maintain a count as we read the metadata.
        table_count = 0

        (0..63).each do |i|
            if (stream.valid & (1 << i)) != 0 then
                # bit i is valid; check to see if we have a class for reading it.
                puts "table #{i} present."
                raise "don't know how to parse valid table #{i}!" if tables_classes[0].table_id != i

                rows = stream.rows[table_count]

                # read a bunch of rows (note: row indices start at 1)
                puts "reading #{rows} rows from table #{i}..."
                (1..rows).each do |row_index|
                    row = tables_classes[0].read(f, row_index, stream.heap_sizes)
                end

                # move on to the next table
                table_count += 1
                tables_classes.slice!(0)
            else
                puts "table #{i} not present."
            end
        end

        # puts "module table starts #{f.read_word.to_s(16)}, #{f.read_word}, #{f.read_word}, #{f.read_word}, #{f.read_word}"

        return stream
    end

    attr_accessor :reserved_0, :major_version, :minor_version, :heap_sizes,
        :reserved_7, :valid, :sorted, :rows, :tables
end

class BlobHeap
    def BlobHeap.read(f, len)
        heap = BlobHeap.new

        # read whole heap at once
        data = f.read(len)
        ofs = 0
        idx = 0

        loop do
            blob_len = nil

            case data[ofs].ord
            when (0..0x7f)
                # 0xxx_xxxxb: length is encoded in lower seven bits
                blob_len = data[ofs].ord & 0x7f
                ofs += 1
            when (0x80..0xbf)
                # 10xx_xxxxb: length is encoded in lower six bits + next byte
                blob_len = ((data[ofs].ord & 0x3f) << 8) + data[ofs + 1].ord
                ofs += 2
            when (0xc0..0xdf)
                # 110x_xxxxb: length is encoded in lower five bits + next three bytes
                blob_len = ((data[ofs].ord & 0x1f) << 24) + 
                    (data[ofs + 1].ord << 16) + (data[ofs + 2].ord << 8) +
                    data[ofs + 3].ord
                ofs += 4
            else
                raise "invalid length encoding"
            end

            heap.blobs[idx] = data[ofs...(ofs + blob_len)]
            ofs += blob_len
            idx += 1

            if (ofs >= len) then
                break
            end
        end

        heap
    end

    def initialize
        self.blobs = []
    end

    attr_accessor :blobs
end

class MetadataRoot
    def MetadataRoot.read(f)
        f.extend BinaryIO
        root = MetadataRoot.new

        signature = f.read_dword
        raise "invalid metadata signature" if signature != 0x424A5342

        root.major_version = f.read_word
        root.minor_version = f.read_word

        f.read_dword # reserved field: ignored

        root.length = f.read_dword
        root.version = f.read(root.length)

        # according to ECMA-335, the length of the version is root.length
        # bytes, but the next field starts at 4 * ceil(root.length / 4)
        # bytes after version.
        x = (root.length / 4.0).ceil * 4
        f.read(x - root.length) # discard padding

        root.flags = f.read_word
        root.streams = f.read_word

        root.stream_headers = []

        root.streams.times do |i|
            root.stream_headers[i] = StreamHeader.read(f)
        end

        return root
    end

    attr_accessor :major_version, :minor_version, :reserved, :length, :version,
        :flags, :streams, :stream_headers
end

class Assembly
    def Assembly.read(f)
        exe = PECOFF::Exe.read(f)
        asm = Assembly.new(exe)

        cli_header_loc = exe.pe_opt_header.data_directory[:cli_header]

        if cli_header_loc.nil? || cli_header_loc[1] == 0 then
            raise "image doesn't contain a CLI header!"
            return nil
        end

        # read CLI header
        f.pos = exe.rva_to_offset(cli_header_loc[0])
        asm.cli_header = CLIHeader.read(f)

        # read metadata root
        mdroot_ofs = f.pos = exe.rva_to_offset(asm.cli_header.metadata[0])
        asm.metadata_root = MetadataRoot.read(f)

        # read strings heap
        strings_stream = (asm.metadata_root.stream_headers.select do |stream| 
            stream.name =~ /^#Strings/
        end)[0]
        f.pos = mdroot_ofs + strings_stream.offset
        asm.strings_heap = StringsHeap.read(f, strings_stream.size) 

        # read US heap
        us_stream = (asm.metadata_root.stream_headers.select do |stream| 
            stream.name =~ /^#US/
        end)[0]
        f.pos = mdroot_ofs + us_stream.offset
        asm.us_heap = BlobHeap.read(f, us_stream.size)

        # read blob heap
        blob_stream = (asm.metadata_root.stream_headers.select do |stream| 
            stream.name =~ /^#Blob/
        end)[0]
        f.pos = mdroot_ofs + blob_stream.offset
        asm.blob_heap = BlobHeap.read(f, blob_stream.size)

        # read squiggle stream
        squiggle = (asm.metadata_root.stream_headers.select do |stream| 
            stream.name =~ /^#~/
        end)[0]
        f.pos = mdroot_ofs + squiggle.offset
        asm.squiggle_stream = SquiggleStream.read(f, squiggle.size)

        return asm 
    end

    def initialize(image)
        self.pecoff_image = image
    end

    attr_accessor :pecoff_image
    attr_accessor :cli_header
    attr_accessor :metadata_root

    attr_accessor :strings_heap
    attr_accessor :us_heap
    attr_accessor :blob_heap
    attr_accessor :squiggle_stream
end

end