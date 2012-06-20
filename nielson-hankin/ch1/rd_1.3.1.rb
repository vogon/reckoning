def unify(rdset1, rdset2)
    all_labels = (rdset1.keys + rdset2.keys).uniq

    unified = {}

    all_labels.each do |label|
        defs1 = rdset1[label]
        defs2 = rdset2[label]

        unified[label] = (defs1 + defs2).uniq
    end

    puts "unify: #{rdset1} + #{rdset2} => #{unified}"

    unified
end

def RD_init(program)
    rd = {:program => program,
          :control_flow => program.control_flow(nil, nil).uniq,
          :entry => {},
          :exit => {}}

    program.labels.each do |label|
        rd[:entry][label] = {}
        rd[:exit][label] = {}
    end

    rd
end

def RD_enter(rd_rec, label)
    flows_in = rd_rec[:control_flow].select { |flow| flow[1] == label }
    puts "flows into label: #{flows_in}"
    labels_to_unify = flows_in.map { |flow| flow[0] }.select {|label| label != nil}
    puts "labels to unify RD_exit: #{labels_to_unify}"
    unified = labels_to_unify.reduce({}) { |memo, label| unify(memo, rd_rec[:exit][label]) }

    unified
end

def solve(program)
    rdr = RD_init(program)

    10.times do
        program.labels.each do |label|
            rdr[:exit][label] = program[label].RD_exit(rdr[:entry][label])
        end

        puts "rd_rec after exit: #{rdr}"

        program.labels.each do |label|
            rdr[:entry][label] = RD_enter(rdr, label)
        end

        puts "rd_rec after enter: #{rdr}"
    end

    rdr
end