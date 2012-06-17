require './exe'
require './helpers'

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

class MetadataRoot
    def MetadataRoot.read(f)
        f.extend BinaryIO
        root = MetadataRoot.new

        signature = f.read_dword
        signature == 0x424A5342 or raise "invalid metadata signature"

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
        f.pos = exe.rva_to_offset(asm.cli_header.metadata[0])
        asm.metadata_root = MetadataRoot.read(f)

        return asm
    end

    def initialize(image)
        self.pecoff_image = image
    end

    attr_accessor :pecoff_image
    attr_accessor :cli_header
    attr_accessor :metadata_root
end

end