module LE
    def LE.byte(ch0)
        ch0.ord
    end

    def LE.word(ch0, ch1)
        (ch1.ord << 8) + ch0.ord
    end

    def LE.dword(ch0, ch1, ch2, ch3)
        (ch3.ord << 24) + (ch2.ord << 16) + (ch1.ord << 8) + ch0.ord
    end

    def LE.qword(ch0, ch1, ch2, ch3, ch4, ch5, ch6, ch7)
        (ch7.ord << 56) + (ch6.ord << 48) + (ch5.ord << 40) +
        (ch4.ord << 32) + (ch3.ord << 24) + (ch2.ord << 16) +
        (ch1.ord << 8) + ch0.ord
    end
end

module StreamHelpers
    def byte_at(ofs)
        LE.byte(self[ofs])
    end

    def word_at(ofs)
        LE.word(self[ofs], self[ofs + 1])
    end

    def dword_at(ofs)
        LE.dword(self[ofs], self[ofs + 1], self[ofs + 2], self[ofs + 3])
    end

    def qword_at(ofs)
        LE.qword(self[ofs], self[ofs + 1], self[ofs + 2], self[ofs + 3],
            self[ofs + 4], self[ofs + 5], self[ofs + 6], self[ofs + 7])
    end
end

module BinaryIO
    def read_byte
        str = self.read(1)
        LE.byte(str[0])
    end

    def read_word
        str = self.read(2)
        LE.word(str[0], str[1])
    end

    def read_dword
        str = self.read(4)
        LE.dword(str[0], str[1], str[2], str[3])
    end

    def read_qword
        str = self.read(8)
        LE.qword(str[0], str[1], str[2], str[3], str[4], str[5], str[6], str[7])
    end

    def read_rva_size
        rva = self.read_dword
        size = self.read_dword

        return rva, size
    end
end
