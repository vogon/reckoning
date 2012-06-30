require './helpers'

module CLR

def self.make_token(table_sym, index)
    table = CLR::Tables.const_get(table_sym)
    table[index]
end

def self.make_codedindex_token(table_syms, size, tag_width, codedindex)
    # puts "m_ci_t(#{table_syms}, #{size}, #{tag_width}, #{codedindex})"
    index_mask = (1 << (size - tag_width + 1)) - 1
    index = codedindex & index_mask
    tag = codedindex >> (size - tag_width)

    table_syms[tag] or raise "couldn't figure out table: coded index is #{codedindex.to_s(2)}, tag is #{tag}, tables are #{table_syms}"
    table = CLR::Tables.const_get(table_syms[tag])
    table[index]
end

# most of the wizardry here is due to Rob Hanlon (@ohwillie)
class MDRow
    class << self
        def dump
            puts @schema
        end

        # read 4 bytes if block is true; otherwise, read 2 bytes
        def read_index(f)
            if yield then
                f.read_dword
            else
                f.read_word
            end
        end

        def read_size(f, sz)
            case sz
            when 16 then f.read_word
            when 32 then f.read_dword
            end
        end

        def read(f, index, heap_sizes)
            f.extend BinaryIO
            row = self.new(index)
            value = nil

            @schema.each do |column|
                case column[:type]
                when :uint8 then
                    value = f.read_byte
                when :uint16 then
                    value = f.read_word
                when :uint32 then
                    value = f.read_dword
                when :string_index then
                    value = read_index(f) { heap_sizes.big_string_heap? }
                when :blob_index then
                    value = read_index(f) { heap_sizes.big_blob_heap? }
                when :guid_index then
                    value = read_index(f) { heap_sizes.big_guid_heap? }
                when :md_index then
                    size = (column[:size]).call(f)
                    rawvalue = read_size(f, size)
                    value = (column[:mapper]).call(rawvalue, size)
                end

                # puts "#{column[:name]}: type #{column[:type]}, value #{value.to_s(16)}"

                row.send "#{column[:name].to_s}=", value
            end

            row
        end

        def [](index)
            (self.table_id << 24) | index
        end

        def table_id
            # puts "table_id"

            @table_id
        end

        private
        def table_id=(id)
            # puts "table_id = #{id}"

            @table_id = id
        end

        def byte(name)
            @schema << { :name => name, :type => :uint8 }
            attr_accessor name
        end

        def word(name)
            @schema << { :name => name, :type => :uint16 }
            attr_accessor name
        end

        def dword(name)
            @schema << { :name => name, :type => :uint32 }
            attr_accessor name
        end

        def string_index(name)
            @schema << { :name => name, :type => :string_index }
            attr_accessor name
        end

        def blob_index(name)
            @schema << { :name => name, :type => :blob_index }
            attr_accessor name
        end

        def guid_index(name)
            @schema << { :name => name, :type => :guid_index }
            attr_accessor name
        end

        def md_index(table, name)
            # fixme
            size = Proc.new { |f| 16 }
            mapper = Proc.new { |index, size| CLR::make_token(table, index) }

            @schema << { :name => name, :type => :md_index, :size => size, :mapper => mapper }
            attr_accessor name
        end

        def md_codedindex(tables, name)
            # fixme
            size = Proc.new { |f| 16 }
            tag_width = Math.log(tables.length, 2).ceil

            mapper = Proc.new { |index, size| CLR::make_codedindex_token(tables, size, tag_width, index) }

            @schema << { :name => name, :type => :md_index, :size => size, :mapper => mapper }
            attr_accessor name
        end

        def inherited(descendant)
            descendant.instance_eval do
                @schema = []
            end
        end
    end

    def initialize(index)
        self.index = index
    end

    def token
        self.class[self.index]
    end

    attr_accessor :index
end

module Tables

ObjectSpace.each_object(MDRow.singleton_class).each do |klass|
    remove_const klass.name.gsub(/^.*::/, '') if klass < MDRow
end

TypeDefOrRef = [:MDTypeDef, :MDTypeRef, :MDTypeSpec]
HasConstant = [:MDField, :MDParam, :MDProperty]
HasCustomAttribute = [:MDMethodDef, :MDField, :MDTypeRef, :MDTypeDef, :MDParam, :MDInterfaceImpl, :MDMemberRef,
        :MDModule, :MDPermission, :MDProperty, :MDEvent, :MDStandAloneSig, :MDModuleRef, :MDTypeSpec, :MDAssembly,
        :MDAssemblyRef, :MDFile, :MDExportedType, :MDManifestResource, :MDGenericParam, :MDGenericParamConstant,
        :MDMethodSpec]
HasFieldMarshal = [:MDField, :MDParam]
HasDeclSecurity = [:MDTypeDef, :MDMethodDef, :MDAssembly]
MemberRefParent = [:MDTypeDef, :MDTypeRef, :MDModuleRef, :MDModuleDef, :MDTypeSpec]
HasSemantics = [:MDEvent, :MDProperty]
MethodDefOrRef = [:MDMethodDef, :MDMemberRef]
MemberForwarded = [:MDField, :MDMethodDef]
Implementation = [:MDFile, :MDAssemblyRef, :MDExportedType]
CustomAttributeType = [nil, nil, :MDMethodDef, :MDMemberRef, nil]
ResolutionScope = [:MDModule, :MDModuleRef, :MDAssemblyRef, :MDTypeRef]
TypeOrMethodDef = [:MDTypeDef, :MDMethodDef]

class MDModule < MDRow
    self.table_id = 0x00

    word :generation
    string_index :name
    guid_index :mvid
    guid_index :encid
end

class MDTypeRef < MDRow
    self.table_id = 0x01

    md_codedindex ResolutionScope, :resolution_scope
    string_index :type_name
    string_index :type_namespace
end

class MDTypeDef < MDRow
    self.table_id = 0x02

    dword :flags
    string_index :type_name
    string_index :type_namespace
    md_codedindex TypeDefOrRef, :extends
    md_index :MDField, :field_list
    md_index :MDMethodDef, :method_list
end

class MDField < MDRow
    self.table_id = 0x04

    word :flags
    string_index :name
    blob_index :signature
end

class MDMethodDef < MDRow
    self.table_id = 0x06

    dword :rva
    word :impl_flags
    word :flags
    string_index :name
    blob_index :signature
    md_index :MDParam, :param_list
end

class MDParam < MDRow
    self.table_id = 0x08

    word :flags
    word :sequence
    string_index :name
end

class MDInterfaceImpl < MDRow
    self.table_id = 0x09

    md_index :MDTypeDef, :klass
    md_codedindex TypeDefOrRef, :interface
end

class MDMemberRef < MDRow
    self.table_id = 0x0A

    md_codedindex MemberRefParent, :klass
    string_index :name
    blob_index :signature
end

class MDConstant < MDRow
    self.table_id = 0x0B

    byte :type
    byte :reserved_1
    md_codedindex HasConstant, :parent
    blob_index :value
end

class MDCustomAttribute < MDRow
    self.table_id = 0x0C

    md_codedindex HasCustomAttribute, :parent
    md_codedindex CustomAttributeType, :type
    blob_index :value
end

class MDFieldMarshal < MDRow
    self.table_id = 0x0D

    md_codedindex HasFieldMarshal, :parent
    blob_index :native_type
end

class MDDeclSecurity < MDRow
    self.table_id = 0x0E

    word :action
    md_codedindex HasDeclSecurity, :parent
    blob_index :permission_set
end

class MDClassLayout < MDRow
    self.table_id = 0x0F

    word :packing_size
    dword :class_size
    md_index :MDTypeDef, :parent
end

class MDStandAloneSig < MDRow
    self.table_id = 0x11

    blob_index :signature
end

class MDEventMap < MDRow
    self.table_id = 0x12

    md_index :MDTypeDef, :parent
    md_index :MDEvent, :event_list
end

class MDEvent < MDRow
    self.table_id = 0x14

    word :event_flags
    string_index :name
    md_codedindex TypeDefOrRef, :event_type
end

class MDPropertyMap < MDRow
    self.table_id = 0x15

    md_index :MDTypeDef, :parent
    md_index :MDProperty, :property_list
end

class MDProperty < MDRow
    self.table_id = 0x17

    word :flags
    string_index :name
    blob_index :type
end

class MDMethodSemantics < MDRow
    self.table_id = 0x18

    word :semantics
    md_index :MDMethodDef, :method
    md_codedindex HasSemantics, :association
end

class MDModuleRef < MDRow
    self.table_id = 0x1A

    string_index :name
end

class MDTypeSpec < MDRow
    self.table_id = 0x1B

    blob_index :signature
end

class MDAssembly < MDRow
    self.table_id = 0x20

    dword :hash_alg_id
    word :major_version
    word :minor_version
    word :build_number
    word :revision_number
    dword :flags
    blob_index :public_key
    string_index :name
    string_index :culture
end

class MDAssemblyRef < MDRow
    self.table_id = 0x23

    word :major_version
    word :minor_version
    word :build_number
    word :revision_number
    dword :flags
    blob_index :public_key_or_token
    string_index :name
    string_index :culture
    blob_index :hash_value
end

end # module Tables

end # module CLR