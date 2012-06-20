module Labeled
	attr_accessor :label
end

class Expr
	def initialize
		self.children = []
	end

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

class AExp < Expr
end

class BExp < Expr
end

class Variable < AExp
	def initialize(name)
		name or fail
		self.name = name
	end

	attr_accessor :name
end

class Numeral < AExp
	def initialize(value)
		value or fail
		self.value = value
	end

	attr_accessor :value
end

class OpA < AExp
	def initialize(op, lhs, rhs)
		op or fail
		
		lhsexp = make_aexp(lhs)
		rhsexp = make_aexp(rhs)
		(lhsexp && rhsexp) or fail

		self.op = op.to_sym
		self.children = [lhsexp, rhsexp]
	end

	attr_accessor :op
end

class True < BExp
end

class False < BExp
end

class Not < BExp
	def initialize(b)
		b.is_a? BExp or fail
		self.children = [b]
	end
end

class OpB < BExp
	def initialize(op, lhs, rhs)
		op or fail
		((lhs.is_a? BExp) && (rhs.is_a? BExp)) or fail

		self.op = op.to_sym
		self.children = [lhs, rhs]
	end

	attr_accessor :op
end

class OpR < BExp
	def initialize(op, lhs, rhs)
		op or fail

		lhsexp = make_aexp(lhs)
		rhsexp = make_aexp(rhs)
		(lhsexp && rhsexp) or fail

		self.op = op.to_sym
		self.children = [lhsexp, rhsexp]
	end

	attr_accessor :op
end

class Stmt < Expr
	def control_flow(pred, succ)
		[]
	end

	def labels
		[]
	end

	def [](label)
		nil
	end

	def RD_exit(entry)
		entry
	end
end

class Assign < Stmt
	include Labeled

	def initialize(lhs, rhs, label)
		label or fail

		lhsexp = make_var(lhs)
		rhsexp = make_aexp(rhs)
		(lhsexp && rhsexp) or fail

		self.label = label
		self.children = [lhsexp, rhsexp]
	end

	def control_flow(pred, succ)
		[[pred, label], [label, succ]]
	end

	def [](label)
		(label == self.label) ? self : nil
	end

	def labels
		[label]
	end

	def RD_exit(entry)
		exit = entry.clone
		exit[self.children[0].value] = [label]

		exit
	end
end

class Skip < Stmt
	include Labeled

	def initialize(label)
		label or fail
		self.label = label
	end

	def control_flow(pred, succ)
		[[pred, label], [label, succ]]
	end

	def labels
		[self.label]
	end

	def [](label)
		(label == self.label) ? self : nil
	end
end

class Seq < Stmt
	def initialize(s1, s2)
		((s1.is_a? Stmt) && (s2.is_a? Stmt)) or fail

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

	def labels
		self.children[0].labels + self.children[1].labels
	end

	def [](label)
		(self.children[0])[label] or (self.children[1])[label]
	end
end

class If < Stmt
	include Labeled

	def initialize(cond, label, yes, no)
		label or fail
		((cond.is_a? BExp) && (yes.is_a? Stmt) && (no.is_a? Stmt)) or fail

		self.label = label
		self.children = [cond, yes, no]
	end

	def control_flow(pred, succ)
		yes = self.children[1]
		no = self.children[2]

		yes_flows = yes.control_flow(label, succ)
		no_flows = no.control_flow(label, succ)

		yes_flows + no_flows
	end

	def labels
		self.label + self.children[1].labels + self.children[2].labels
	end

	def [](label)
		((label == self.label) ? self : nil) or (self.children[1])[label] or (self.children[2])[label]
	end
end

class While < Stmt
	include Labeled

	def initialize(cond, label, body)
		label or fail
		((cond.is_a? BExp) && (body.is_a? Stmt)) or fail

		self.label = label
		self.children = [cond, body]
	end

	def control_flow(pred, succ)
		entry_flows = [[pred, label]]
		exit_flows = [[label, succ]]
		body_flows = self.children[1].control_flow(label, label)

		entry_flows + exit_flows + body_flows
	end

	def labels
		[self.label] + self.children[1].labels
	end

	def [](label)
		((label == self.label) ? self : nil) or (self.children[1])[label]
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