class Node
	def initialize(value, label)
		self.value = value
		self.label = label

		self.children = []
	end

	attr_accessor :value, :label
	attr_accessor :children
end

def make_var(value)
	if value.is_a? Variable then
		value
	elsif value.is_a? Symbol then
		Variable.new(value)
	end
end

def make_aexp(value)
	if value.is_a? AExp then
		value
	elsif value.is_a? Fixnum then
		Numeral.new(value)
	elsif value.is_a? Symbol then
		Variable.new(value)
	end
end

class AExp < Node
end

class BExp < Node
end

class Stmt < Node
	def control_flow(pred, succ)
		[]
	end

	def entry
		nil
	end

	def leaves
		[]
	end
end

class Variable < AExp
	def initialize(name)
		name or fail

		super(name, nil)
	end
end

class Numeral < AExp
	def initialize(value)
		value or fail

		super(value, nil)
	end
end

class OpA < AExp
	def initialize(op, lhs, rhs)
		op or fail
		
		lhsexp = make_aexp(lhs)
		rhsexp = make_aexp(rhs)
		(lhsexp && rhsexp) or fail

		super(op.to_sym, nil)
		self.children = [lhsexp, rhsexp]
	end
end

class True < BExp
	def initialize
		super(nil, nil)
	end
end

class False < BExp
	def initialize
		super(nil, nil)
	end
end

class Not < BExp
	def initialize(b)
		b.is_a? BExp or fail

		super(nil, nil)
		self.children = [b]
	end
end

class OpB < BExp
	def initialize(op, lhs, rhs)
		op or fail
		((lhs.is_a? BExp) && (rhs.is_a? BExp)) or fail

		super(op.to_sym, nil)
		self.children = [lhs, rhs]
	end
end

class OpR < BExp
	def initialize(op, lhs, rhs)
		op or fail

		lhsexp = make_aexp(lhs)
		rhsexp = make_aexp(rhs)
		(lhsexp && rhsexp) or fail

		super(op.to_sym, nil)
		self.children = [lhsexp, rhsexp]
	end
end

class Assign < Stmt
	def initialize(lhs, rhs, label)
		label or fail

		lhsexp = make_var(lhs)
		rhsexp = make_aexp(rhs)
		(lhsexp && rhsexp) or fail

		super(nil, label)
		self.children = [lhsexp, rhsexp]
	end

	def control_flow(pred, succ)
		[[pred, label], [label, succ]]
	end

	def entry
		label
	end

	def leaves
		[label]
	end
end

class Skip < Stmt
	def initialize(label)
		label or fail

		super(nil, label)
	end

	def control_flow(pred, succ)
		[[pred, label], [label, succ]]
	end

	def entry
		label
	end

	def leaves
		[label]
	end
end

class Seq < Stmt
	def initialize(s1, s2)
		((s1.is_a? Stmt) && (s2.is_a? Stmt)) or fail

		super(nil, nil)
		self.children = [s1, s2]
	end

	def control_flow(pred, succ)
		s1 = self.children[0]
		s2 = self.children[1]

		s1_flows = s1.control_flow(pred, s2.entry)

		s2_flows = []
		# build flows from each exit of s1 to the entry of s2
		s1.leaves.each do |label|
			s2_flows += s2.control_flow(label, succ)
		end

		s1_flows + s2_flows
	end

	def entry
		self.children[0].entry
	end

	def leaves
		self.children[1].leaves
	end
end

class If < Stmt
	def initialize(cond, label, yes, no)
		label or fail
		((cond.is_a? BExp) && (yes.is_a? Stmt) && (no.is_a? Stmt)) or fail

		super(nil, label)
		self.children = [cond, yes, no]
	end

	def control_flow(pred, succ)
		yes = self.children[1]
		no = self.children[2]

		yes_flows = yes.control_flow(label, succ)
		no_flows = no.control_flow(label, succ)

		yes_flows + no_flows
	end

	def entry
		self.label
	end

	def leaves
		self.children[1].leaves + self.children[2].leaves
	end
end

class While < Stmt
	def initialize(cond, label, body)
		label or fail
		((cond.is_a? BExp) && (body.is_a? Stmt)) or fail

		super(nil, label)
		self.children = [cond, body]
	end

	def control_flow(pred, succ)
		entry_flows = [[pred, label]]
		exit_flows = [[label, succ]]
		body_flows = self.children[1].control_flow(label, label)

		entry_flows + exit_flows + body_flows
	end

	def entry
		self.label
	end

	def leaves
		[self.label]
	end
end

def program(stmts)
	if stmts.length == 0 then
		nil
	elsif stmts.length == 1 then
		stmts[0]
	else
		Seq.new(stmts[0], program(stmts.slice(1..-1)))
	end
end

Factorial = program([
	Assign.new(:y, :x, 1),
	Assign.new(:z, 1, 2),
	While.new(OpR.new(:>, :y, 1), 3,
			   Seq.new(
			   	Assign.new(:z, OpA.new(:*, :z, :y), 4),
			   	Assign.new(:y, OpA.new(:-, :y, 1), 5)
			   )),
	Assign.new(:y, 0, 6)
])