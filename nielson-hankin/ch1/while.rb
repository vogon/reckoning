module Labeled
	attr_accessor :label
end

class Expr
	def variables
		[]
	end
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

	def variables
		[self.name]
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
		self.lhs = lhsexp
		self.rhs = rhsexp
	end

	def variables
		self.lhs.variables | self.rhs.variables
	end

	attr_accessor :op
	attr_accessor :lhs, :rhs
end

class True < BExp
end

class False < BExp
end

class Not < BExp
	def initialize(b)
		b.is_a? BExp or fail
		self.rhs = b
	end

	def variables
		self.rhs.variables
	end

	attr_accessor :rhs
end

class OpB < BExp
	def initialize(op, lhs, rhs)
		op or fail
		((lhs.is_a? BExp) && (rhs.is_a? BExp)) or fail

		self.op = op.to_sym
		self.lhs = lhs
		self.rhs = rhs
	end

	def variables
		self.lhs.variables | self.rhs.variables
	end

	attr_accessor :op
	attr_accessor :lhs, :rhs
end

class OpR < BExp
	def initialize(op, lhs, rhs)
		op or fail

		lhsexp = make_aexp(lhs)
		rhsexp = make_aexp(rhs)
		(lhsexp && rhsexp) or fail

		self.op = op.to_sym
		self.lhs = lhsexp
		self.rhs = rhsexp
	end

	def variables
		self.lhs.variables | self.rhs.variables
	end

	attr_accessor :op
	attr_accessor :lhs, :rhs
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
		self.lhs = lhsexp
		self.rhs = rhsexp
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
		exit[self.lhs.name] = [label]

		exit
	end

	def variables
		self.lhs.variables | self.rhs.variables
	end

	attr_accessor :lhs, :rhs
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

		self.first = s1
		self.second = s2
	end

	def control_flow(pred, succ)
		s1 = self.first
		s2 = self.second

		s1_flows = s1.control_flow(pred, s2.entry)

		s2_flows = []
		# build flows from each exit of s1 to the entry of s2
		s1.leaves.each do |label|
			s2_flows += s2.control_flow(label, succ)
		end

		s1_flows + s2_flows
	end

	def labels
		self.first.labels + self.second.labels
	end

	def [](label)
		self.first[label] or self.second[label]
	end

	def variables
		self.first.variables | self.second.variables
	end

	attr_accessor :first, :second
end

class If < Stmt
	include Labeled

	def initialize(cond, label, yes, no)
		label or fail
		((cond.is_a? BExp) && (yes.is_a? Stmt) && (no.is_a? Stmt)) or fail

		self.label = label
		self.test = cond
		self.yes = yes
		self.no = no
	end

	def control_flow(pred, succ)
		yes_flows = self.yes.control_flow(label, succ)
		no_flows = self.no.control_flow(label, succ)

		yes_flows + no_flows
	end

	def labels
		self.label + self.yes.labels + self.no.labels
	end

	def [](label)
		((label == self.label) ? self : nil) or (self.yes)[label] or (self.no)[label]
	end

	def variables
		self.test.variables | self.yes.variables | self.no.variables
	end

	attr_accessor :test
	attr_accessor :yes, :no
end

class While < Stmt
	include Labeled

	def initialize(cond, label, body)
		label or fail
		((cond.is_a? BExp) && (body.is_a? Stmt)) or fail

		self.label = label
		self.test = cond
		self.body = body
	end

	def control_flow(pred, succ)
		entry_flows = [[pred, label]]
		exit_flows = [[label, succ]]
		body_flows = self.body.control_flow(label, label)

		entry_flows + exit_flows + body_flows
	end

	def labels
		[self.label] + self.body.labels
	end

	def [](label)
		((label == self.label) ? self : nil) or (self.body)[label]
	end

	def variables
		self.test.variables | self.body.variables
	end

	attr_accessor :test
	attr_accessor :body
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