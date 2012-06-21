require './while'

class Stmt < Expr
    def RD_exit(entry)
        entry
    end
end

class Assign < Stmt
    def RD_exit(entry)
        exit = entry.clone
        exit[self.lhs.name] = [label]

        exit
    end
end

def RD_init(program)
    rd = {:program => program,
          :control_flow => program.flow,
          :entry => Hash[program.labels.map {|label| [label, Hash[program.variables.map {|var| [var, []]}]]}],
          :exit => Hash[program.labels.map {|label| [label, Hash[program.variables.map {|var| [var, []]}]]}]}

    rd
end

def RD_enter(rd_rec, label)
    program = rd_rec[:program]
    flows_in = rd_rec[:control_flow].select { |flow| flow[1] == label }
    # puts "flows into label: #{flows_in}"

    unified = Hash[program.variables.map {|var| [var, []]}]

    flows_in.each do |flow|
        # identify label departing
        from_label = flow[0]
        rd_exit = rd_rec[:exit][from_label]

        # puts "rd_exit from #{from_label}: #{rd_exit}"

        # for each variable, merge rd_exit with unified
        program.variables.each do |var|
            unified[var] |= rd_exit[var]
        end
    end

    # puts "after merge: #{unified}"

    unified
end

def solve(program)
    rdr = RD_init(program)

    10.times do
        program.labels.each do |label|
            rdr[:exit][label] = program[label].RD_exit(rdr[:entry][label])
        end

        # puts "rd_rec after exit: #{rdr}"

        program.labels.each do |label|
            rdr[:entry][label] = RD_enter(rdr, label)
        end

        # puts "rd_rec after enter: #{rdr}"
    end

    rdr[:entry]
end