require './flags'
require './helpers'

module PECOFF

class PEHeader
    module Machine
        Unknown = 0x0;
        AM33 = 0x1d3;
        AMD64 = 0x8664;
        ARM = 0x1c0;
        ARMv7 = 0x1c4;
        EBC = 0xebc;
        I386 = 0x14c;
        IA64 = 0x200;
        M32R = 0x9041;
        MIPS16 = 0x266;
        MIPSFPU = 0x366;
        MIPSFPU16 = 0x466;
        PowerPC = 0x1f0;
        PowerPCFP = 0x1f1;
        R4000 = 0x166;
        SH3 = 0x1a2;
        SH3DSP = 0x1a3;
        SH4 = 0x1a6;
        SH5 = 0x1a8;
        Thumb = 0x1c2;
        WCEMIPSV2 = 0x169;
    end

    class Characteristics < Flags
        enum_attr :relocs_stripped, 0x0001
        enum_attr :executable_image, 0x0002
        enum_attr :line_nums_stripped, 0x0004
        enum_attr :local_syms_stripped, 0x0008
        enum_attr :aggressive_ws_trim, 0x0010
        enum_attr :large_address_aware, 0x0020
        enum_attr :bytes_reversed_lo, 0x0080
        enum_attr :is_32bit_machine, 0x0100
        enum_attr :debug_stripped, 0x0200
        enum_attr :removable_run_from_swap, 0x0400
        enum_attr :net_run_from_swap, 0x0800
        enum_attr :system, 0x1000
        enum_attr :dll, 0x2000
        enum_attr :up_system_only, 0x4000
        enum_attr :bytes_reversed_hi, 0x8000
    end

    def PEHeader.read(f)
        f.extend BinaryIO
        hdr = PEHeader.new

        hdr.machine = f.read_word
        hdr.n_sections = f.read_word
        hdr.time_date = f.read_dword
        hdr.ofs_symbol_table = f.read_dword
        hdr.n_symbols = f.read_dword
        hdr.optional_header_sz = f.read_word
        hdr.characteristics = Characteristics.new(f.read_word)

        return hdr
    end

    attr_accessor :machine, :n_sections, :time_date, :ofs_symbol_table, 
        :n_symbols, :optional_header_sz, :characteristics
end

class PEOptionalHeader
    module Magic
        PE32 = 0x010b;
        PE32Plus = 0x020b;
    end

    def PEOptionalHeader.read(f)
        f.extend BinaryIO
        hdr = PEOptionalHeader.new

        hdr.magic = f.read_word
        hdr.major_linker_version = f.read_byte
        hdr.minor_linker_version = f.read_byte
        hdr.size_of_code = f.read_dword
        hdr.size_of_data = f.read_dword
        hdr.size_of_bss = f.read_dword
        hdr.addr_of_entry_point = f.read_dword
        hdr.base_of_code = f.read_dword

        if hdr.is_pe32? then
            hdr.base_of_data = f.read_dword
        end

        return hdr
    end

    def is_pe32?
        self.magic == Magic::PE32
    end

    def is_pe32plus?
        self.magic == Magic::PE32Plus
    end

    attr_accessor :magic, :major_linker_version, :minor_linker_version,
        :size_of_code, :size_of_data, :size_of_bss, :addr_of_entry_point,
        :base_of_code, :base_of_data
end

class PEWin32DataDirectory
    def PEWin32DataDirectory.read(f, n)
        f.extend BinaryIO

        raw = []

        n.times do |i|
            rva = f.read_dword
            size = f.read_dword

            raw[i] = [rva, size]
        end

        return PEWin32DataDirectory.new(raw)
    end

    def initialize(raw)
        if raw.is_a? Array then
            @raw_data_dir = raw
        else
            raise "idk"
        end
    end

    def name_to_idx(name)
        well_known = {
            :export_tbl => 0,
            :import_tbl => 1,
            :resource_tbl => 2,
            :exception_tbl => 3,
            :certificate_tbl => 4,
            :base_reloc_tbl => 5,
            :debug => 6,
            :copyright => 7,
            :global_ptr => 8,
            :tls_tbl => 9,
            :load_config_tbl => 10,
            :bound_import_tbl => 11,
            :iat => 12,
            :delay_import_descriptor => 13,
            :cli_header => 14
        }

        return well_known[name]
    end

    def [](index)
        if index.is_a? Symbol then
            @raw_data_dir[name_to_idx(index)]
        elsif index.is_a? Fixnum then
            @raw_data_dir[index]
        end
    end

    def []=(index, value)
        if index.is_a? Symbol then
            @raw_data_dir[name_to_idx(index)] = value
        elsif index.is_a? Fixnum then
            @raw_data_dir[index] = value
        end
    end
end

class PEWin32OptionalHeader
    module Subsystem
        Unknown = 0;
        Native = 1;
        WindowsGUI = 2;
        WindowsCUI = 3;
        POSIXCUI = 7;
        WindowsCEGUI = 9;
        EFIApplication = 10;
        EFIBootServiceDriver = 11;
        EFIRuntimeDriver = 12;
        EFIROM = 13;
        Xbox = 14;
    end

    class DllCharacteristics < Flags
        enum_attr :dynamic_base, 0x0040
        enum_attr :force_integrity, 0x0080
        enum_attr :nx_compat, 0x0100
        enum_attr :no_isolation, 0x0200
        enum_attr :no_seh, 0x0400
        enum_attr :no_bind, 0x0800
        enum_attr :wdm_driver, 0x2000
        enum_attr :terminal_server_aware, 0x8000
    end

    def PEWin32OptionalHeader.read(std, f)
        f.extend BinaryIO
        hdr = PEWin32OptionalHeader.new(std)
        read_addr = nil

        if hdr.is_pe32? then
            read_addr = Proc.new {|f| f.read_dword}
        elsif hdr.is_pe32plus? then
            read_addr = Proc.new {|f| f.read_qword}
        else
            raise "unrecognized image format"
            return nil
        end

        hdr.image_base = read_addr.call f
        hdr.section_alignment = f.read_dword
        hdr.file_alignment = f.read_dword
        hdr.major_os_version = f.read_word
        hdr.minor_os_version = f.read_word
        hdr.major_image_version = f.read_word
        hdr.minor_image_version = f.read_word
        hdr.major_subsystem_version = f.read_word
        hdr.minor_subsystem_version = f.read_word
        hdr.win32_version_value = f.read_dword
        hdr.size_of_image = f.read_dword
        hdr.size_of_headers = f.read_dword
        hdr.checksum = f.read_dword
        hdr.subsystem = f.read_word
        hdr.dll_characteristics = DllCharacteristics.new(f.read_word)
        hdr.size_of_stack_reserve = read_addr.call f
        hdr.size_of_stack_commit = read_addr.call f
        hdr.size_of_heap_reserve = read_addr.call f
        hdr.size_of_heap_commit = read_addr.call f
        hdr.loader_flags = f.read_dword
        hdr.num_rva_and_sizes = f.read_dword

        # read data directory
        hdr.data_directory = 
            PEWin32DataDirectory.read(f, hdr.num_rva_and_sizes)

        return hdr
    end

    def initialize(std_header)
        @std_header = std_header
    end

    def method_missing(name, *args)
        # puts "method missing #{name}: #{args}"
        @std_header.send name, *args
    end

    attr_accessor :image_base, :section_alignment, :file_alignment,
        :major_os_version, :minor_os_version, :major_image_version,
        :minor_image_version, :major_subsystem_version, 
        :minor_subsystem_version, :win32_version_value, :size_of_image,
        :size_of_headers, :checksum, :subsystem, :dll_characteristics,
        :size_of_stack_reserve, :size_of_stack_commit, :size_of_heap_reserve,
        :size_of_heap_commit, :loader_flags

    attr_accessor :num_rva_and_sizes, :data_directory
end

class SectionHeader
    class Characteristics < Flags
        enum_attr :type_no_pad,             0x00000008
        enum_attr :cnt_code,                0x00000020
        enum_attr :cnt_initialized_data,    0x00000040
        enum_attr :cnt_uninitialized_data,  0x00000080
        enum_attr :lnk_other,               0x00000100
        enum_attr :lnk_info,                0x00000200
        enum_attr :lnk_remove,              0x00000800
        enum_attr :lnk_comdat,              0x00001000
        enum_attr :gprel,                   0x00008000
        enum_attr :mem_purgeable,           0x00020000
        enum_attr :mem_16bit,               0x00020000
        enum_attr :mem_locked,              0x00040000
        enum_attr :mem_preload,             0x00080000
        enum_attr :lnk_nreloc_ovfl,         0x01000000
        enum_attr :mem_discardable,         0x02000000
        enum_attr :mem_not_cached,          0x04000000
        enum_attr :mem_not_paged,           0x08000000
        enum_attr :mem_shared,              0x10000000
        enum_attr :mem_execute,             0x20000000
        enum_attr :mem_read,                0x40000000
        enum_attr :mem_write,               0x80000000

        def alignment
            align_bits = (@attrs >> 20) & 0xf

            if align_bits == 0 then
                nil
            else
                1 << (align_bits - 1)
            end
        end

        def alignment=(n)
            raise "todo"
        end
    end

    def SectionHeader.read(f)
        f.extend BinaryIO
        hdr = SectionHeader.new

        hdr.name = f.read(8)
        hdr.virtual_size = f.read_dword
        hdr.virtual_addr = f.read_dword
        hdr.size_of_raw_data = f.read_dword
        hdr.ptr_to_raw_data = f.read_dword
        hdr.ptr_to_relocs = f.read_dword
        hdr.ptr_to_line_numbers = f.read_dword
        hdr.n_relocs = f.read_word
        hdr.n_line_numbers = f.read_word
        hdr.characteristics = Characteristics.new(f.read_dword)

        hdr
    end

    attr_accessor :name, :virtual_size, :virtual_addr, :size_of_raw_data,
        :ptr_to_raw_data, :ptr_to_relocs, :ptr_to_line_numbers, :n_relocs,
        :n_line_numbers, :characteristics
end

class Exe
    def Exe.read(f)
        f.extend BinaryIO
        exe = Exe.new

        stub = f.read(0x40)
        stub.extend StreamHelpers

        # read offset of PE signature
        sig_offset = stub.dword_at(0x3c)
        # glue the rest of the stub on
        stub.concat f.read(sig_offset - 0x40)

        exe.msdos_stub = stub

        # verify signature
        sig = f.read(4)
        sig == "PE\0\0" or return nil

        exe.pe_header = PEHeader.read(f)
        
        std_opt_header = PEOptionalHeader.read(f)
        win32_opt_header = 
            PEWin32OptionalHeader.read(std_opt_header, f)

        exe.pe_opt_header = win32_opt_header

        exe.section_headers = []

        exe.pe_header.n_sections.times do |i|
            exe.section_headers[i] = SectionHeader.read(f)
        end

        return exe
    end

    def rva_to_offset(rva)
        section_headers.each do |section|
            if rva >= section.virtual_addr &&
               rva < section.virtual_addr + section.virtual_size then
                puts "#{rva} within #{section.name}:[#{section.virtual_addr}+#{section.virtual_size}]"
                offset_within_section = rva - section.virtual_addr
                return section.ptr_to_raw_data + offset_within_section
            else
                puts "#{rva} outside of #{section.name}[#{section.virtual_addr}+#{section.virtual_size}]"
            end
        end
    end

    attr_accessor :msdos_stub, :pe_header, :pe_opt_header
    attr_accessor :section_headers
end

end
