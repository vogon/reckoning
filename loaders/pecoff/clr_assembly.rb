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
        hdr.metadata = f.read_qword
        hdr.flags = Characteristics.new(f.read_dword)
        hdr.entry_point_token = f.read_dword
        hdr.resources = f.read_qword
        hdr.strong_name_signature = f.read_qword
        hdr.code_manager_table = f.read_qword
        hdr.vtable_fixups = f.read_qword
        hdr.export_address_table_jumps = f.read_qword
        hdr.managed_native_header = f.read_qword

        return hdr
    end

    attr_accessor :cb, :major_runtime_version, :minor_runtime_version,
        :metadata, :flags, :entry_point_token, :resources, 
        :strong_name_signature, :code_manager_table, :vtable_fixups,
        :export_address_table_jumps, :managed_native_header
end

class Assembly
    def Assembly.read(f)
        exe = PECOFF::Exe.read(f)
        asm = Assembly.new(exe)

        cli_header = exe.pe_opt_header.data_directory[:cli_header]

        if cli_header.nil? || cli_header.size == 0 then
            raise "image doesn't contain a CLI header!"
            return nil
        end

        # seek to CLI header
        f.pos = exe.rva_to_offset(cli_header[0])

        asm.cli_header = CLIHeader.read(f)

        return asm
    end

    def initialize(image)
        self.pecoff_image = image
    end

    attr_accessor :pecoff_image
    attr_accessor :cli_header
end

end