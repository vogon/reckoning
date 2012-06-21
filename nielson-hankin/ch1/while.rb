module Block
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
	def blocks
		[]
	end

	def labels
		self.blocks.map { |block| block.label }
	end

	def [](label)
		self.blocks.detect { |block| block.label == label }
	end

	def init
		nil
	end

	def final
		nil
	end

	def flow
		[]
	end

	def flowR
		self.flow.map { |flow| [flow[1], flow[0]] }
	end
end

class Assign < Stmt
	include Block

	def initialize(lhs, rhs, label)
		label or fail

		lhsexp = make_var(lhs)
		rhsexp = make_aexp(rhs)
		(lhsexp && rhsexp) or fail

		self.label = label
		self.lhs = lhsexp
		self.rhs = rhsexp
	end

	def blocks
		[self]
	end

	def variables
		self.lhs.variables | self.rhs.variables
	end

	def init
		self.label
	end

	def final
		[self.label]
	end

	attr_accessor :lhs, :rhs
end

class Skip < Stmt
	include Block

	def initialize(label)
		label or fail
		self.label = label
	end

	def blocks
		[self]
	end

	def init
		self.label
	end

	def final
		[self.label]
	end
end

class Seq < Stmt
	def initialize(s1, s2)
		((s1.is_a? Stmt) && (s2.is_a? Stmt)) or fail

		self.first = s1
		self.second = s2
	end

	def blocks
		self.first.blocks + self.second.blocks
	end

	def variables
		self.first.variables | self.second.variables
	end

	def init
		self.first.init
	end

	def final
		self.second.final
	end

	def flow
		control_transfers = self.first.final.map { |flabel| [flabel, self.second.init] }

		self.first.flow | self.second.flow | control_transfers
	end

	attr_accessor :first, :second
end

class If < Stmt
	include Block

	def initialize(cond, label, yes, no)
		label or fail
		((cond.is_a? BExp) && (yes.is_a? Stmt) && (no.is_a? Stmt)) or fail

		self.label = label
		self.test = cond
		self.yes = yes
		self.no = no
	end

	def blocks
		[self] + self.yes.blocks + self.no.blocks
	end

	def variables
		self.test.variables | self.yes.variables | self.no.variables
	end

	def init
		self.label
	end

	def final
		self.yes.final | self.no.final
	end

	def flow
		self.yes.flow | self.no.flow | [[self.label, self.yes.init], [self.label, self.no.init]]
	end

	attr_accessor :test
	attr_accessor :yes, :no
end

class While < Stmt
	include Block

	def initialize(cond, label, body)
		label or fail
		((cond.is_a? BExp) && (body.is_a? Stmt)) or fail

		self.label = label
		self.test = cond
		self.body = body
	end

	def blocks
		[self] + self.body.blocks
	end

	def variables
		self.test.variables | self.body.variables
	end

	def init
		self.label
	end

	def final
		[self.label]
	end

	def flow
		test_passed_flow = [[self.label, self.body.init]]
		loop_flows = self.body.final.map { |flabel| [flabel, self.label] }

		self.body.flow | test_passed_flow | loop_flows
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

Folder = program([
	Assign.new(:x, 10, 1),
	Assign.new(:y, OpA.new(:+, :x, 10), 2),
	Assign.new(:z, OpA.new(:+, :y, 10), 3)
])

Power = program([
	Assign.new(:z, 1, 1),
	While.new(OpR.new(:>, :x, 0), 2,
				Seq.new(
				 Assign.new(:z, OpA.new(:*, :z, :y), 3),
				 Assign.new(:x, OpA.new(:-, :x, 1), 4)
				))
])