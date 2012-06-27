# stolen from stack overflow [insert citation here], which in turn stole it from RAPI
class Flags
    class << self
        def all
            @flags
        end

        private
        def inherited(descendant)
            descendant.instance_eval do
                @flags = {}
            end
        end

        private
        def enum_attr(name, num)
            name = name.to_s
            namesym = name.to_sym

            @flags[namesym] = num

            define_method(name + '?') do
                @attrs & num != 0
            end

            define_method(name + '=') do |set|
                if set
                    @attrs |= num
                else
                    @attrs &= ~num
                end
            end
        end
    end

    public
    def initialize(attrs = 0)
        @attrs = attrs
    end

    def set
        self.class.all.select { |name, val| self.send (name.to_s + "?") }
    end

    def to_i
        @attrs
    end
end
