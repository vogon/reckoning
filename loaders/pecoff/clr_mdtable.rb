require './helpers'

module CLR

def self.make_token(table_sym, index)
    table = const_get(table_sym)
    table[index]
end

def self.make_codedindex_token(table_syms, tag_width, codedindex)
    tag_mask = (1 << tag_width) - 1
    tag = codedindex & tag_mask
    index = codedindex >> tag_width

    table = const_get(table_syms[tag])
    table[index]
end

# most of the wizardry here is due to Rob Hanlon (@ohwillie)
class MDRow
    class << self
        def dump
            puts @schema
        end

        def read(f)
            f.extend BinaryIO

            @schema.each do |column|
                
            end
        end

        def table_id
            # puts "table_id"

            @table_id
        end

        def table_id=(id)
            # puts "table_id = #{id}"

            @table_id = id
        end

        def [](index)
            (self.table_id << 24) | index
        end

        def word(name)
            @schema << { :name => name, :type => :uint16 }
        end

        def dword(name)
            @schema << { :name => name, :type => :uint32 }
        end

        def string_index(name)
            @schema << { :name => name, :type => :string_index }
        end

        def blob_index(name)
            @schema << { :name => name, :type => :blob_index }
        end

        def guid_index(name)
            @schema << { :name => name, :type => :guid_index }
        end

        def md_index(table, name)
            @schema << { :name => name, :type => :md_index, :tables => [table], :mapping => Proc.new { |index| make_token(table, index) } }
        end

        def md_codedindex(tables, tag_width, name)
            @schema << { :name => name, :type => :md_index, :tables => tables, :mapping => Proc.new { |index| make_codedindex_token(tables, tag_width, index) } }
        end

        private

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

ObjectSpace.each_object(MDRow.singleton_class).each do |klass|
    remove_const klass.name.gsub(/^.*::/, '') if klass < MDRow
end

class MDModule < MDRow
    self.table_id = 0x00

    word :generation
    string_index :name
    guid_index :mvid
    guid_index :encid
end

class MDTypeRef < MDRow
    self.table_id = 0x01

    md_codedindex [:MDModule, :MDModuleRef, :MDAssemblyRef, :MDTypeRef], 2, :resolution_scope
    string_index :type_name
    string_index :type_namespace
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

end