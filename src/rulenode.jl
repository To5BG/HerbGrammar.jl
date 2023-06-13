"""
	AbstractRuleNode

Abstract type for representing expression trees.
Expression trees consist of [`RuleNode`](@ref)s and [`Hole`](@ref)s.

- A [`RuleNode`](@ref) represents a certain production rule in the [`Grammar`](@ref).
- A [`Hole`](@ref) is a placeholder where certain rules in the grammar still can be applied. 
"""
abstract type AbstractRuleNode end

"""
	RuleNode <: AbstractRuleNode

A [`RuleNode`](@ref) represents a node in an expression tree.
Each node corresponds to a certain rule in the [`Grammar`](@ref).
A [`RuleNode`](@ref) consists of:

- `ind`: The index of the rule in the [`Grammar`](@ref) which this node is representing.
- `_val`: Field for storing immediately evaluated values
- `children`: The children of this node in the expression tree

!!! compat
	Evaluate immediately functionality is not yet supported by most of Herb.jl.
"""
mutable struct RuleNode <: AbstractRuleNode
	ind::Int # index in grammar
	_val::Any  #value of _() evals
	children::Vector{AbstractRuleNode}
end

"""
	Hole <: AbstractRuleNode

A [`Hole`](@ref) is a placeholder where certain rules from the grammar can still be applied.
The `domain` of a [`Hole`](@ref) defines which rules can be applied.
The `domain` is a bitvector, where the `i`th bit is set to true if the `i`th rule in the grammar can be applied. 
"""
mutable struct Hole <: AbstractRuleNode
	domain::BitVector
end

"""
	RuleNode(ind::Int)

Create a [`RuleNode`](@ref) for the [`Grammar`](@ref) rule with index `ind` and without any children.

!!! warning
	Only use this constructor if you are absolutely certain that a rule is terminal and cannot have children.
	Use [`RuleNode(ind::Int, grammar::Grammar)`] for rules that might have children.
	In general, [`Hole`](@ref)s should be used as a placeholder when the children of a node are not yet known.   
"""
RuleNode(ind::Int) = RuleNode(ind, nothing, AbstractRuleNode[])

"""
	RuleNode(ind::Int, children::Vector{AbstractRuleNode})

Create a [`RuleNode`](@ref) for the [`Grammar`](@ref) rule with index `ind` and `children` as subtrees.
"""
RuleNode(ind::Int, children::Vector{AbstractRuleNode}) = RuleNode(ind, nothing, children)
RuleNode(ind::Int, children::Vector{RuleNode}) = RuleNode(ind, nothing, children)
RuleNode(ind::Int, children::Vector{Hole}) = RuleNode(ind, nothing, children)

"""
	RuleNode(ind::Int, _val::Any)

Create a [`RuleNode`](@ref) for the [`Grammar`](@ref) rule with index `ind`, 
`_val` as immediately evaluated value and no children

!!! warning
	Only use this constructor if you are absolutely certain that a rule is terminal and cannot have children.
	Use [`RuleNode(ind::Int, grammar::Grammar)`] for rules that might have children.
	In general, [`Hole`](@ref)s should be used as a placeholder when the children of a node are not yet known.   

!!! compat
	Evaluate immediately functionality is not yet supported by most of Herb.jl.
"""
RuleNode(ind::Int, _val::Any) = RuleNode(ind, _val, AbstractRuleNode[])

"""
	RuleNode(ind::Int, grammar::Grammar)

Creates a [`RuleNode`](@ref) for the [`Grammar`](@ref) rule with index `ind`, with [`Hole`](@ref)s 
with the appropriate domains as children.
```
RuleNode(ind::Int, grammar::Grammar) = RuleNode(ind, nothing, [Hole(get_domain(grammar, type)) for type ∈ grammar.childtypes[ind]])

```
	RuleNode(ind::Int, _val::Any, grammar::Grammar)

Creates a [`RuleNode`](@ref) for the [`Grammar`](@ref) rule with index `ind`, with immediately evaluated value `_val` 
and with [`Hole`](@ref)s with the appropriate domains as children.

!!! compat
	Evaluate immediately functionality is not yet supported by most of Herb.jl.
"""
RuleNode(ind::Int, _val::Any, grammar::Grammar) = RuleNode(ind, _val, [Hole(get_domain(grammar, type)) for type ∈ grammar.childtypes[ind]])

include("recycler.jl")
    
Base.:(==)(::RuleNode, ::Hole) = false
Base.:(==)(::Hole, ::RuleNode) = false
Base.:(==)(A::RuleNode, B::RuleNode) = 
	(A.ind == B.ind) && 
	length(A.children) == length(B.children) && #required because zip doesn't check lengths
	all(isequal(a, b) for (a, b) ∈ zip(A.children, B.children))
# We do not know how the holes will be expanded yet, so we cannot assume equality even if the domains are equal.
Base.:(==)(A::Hole, B::Hole) = false

function Base.hash(node::RuleNode, h::UInt=zero(UInt))
	retval = hash(node.ind, h)
	for child in node.children
		retval = hash(child, retval)
	end
	return retval
end

function Base.hash(node::Hole, h::UInt=zero(UInt))
	return hash(node.domain, h)
end

function Base.show(io::IO, node::RuleNode; separator=",", last_child::Bool=false)
	print(io, node.ind)
	if !isempty(node.children)
	    print(io, "{")
	    for (i,c) in enumerate(node.children)
		show(io, c, separator=separator, last_child=(i == length(node.children)))
	    end
	    print(io, "}")
	elseif !last_child
	    print(io, separator)
	end
end

function Base.show(io::IO, node::Hole; separator=",", last_child::Bool=false)
	print(io, "hole[$(node.domain)]")
	if !last_child
		print(io, separator)
	end
end

"""
	Base.length(root::RuleNode)

Return the number of nodes in the tree rooted at root.
Holes don't count.
"""
function Base.length(root::RuleNode)
	retval = 1
	for c in root.children
	    retval += length(c)
	end
	return retval
end

"""
	Base.length(root::RuleNode)

Return the number of nodes in the tree rooted at root.
Holes don't count.
"""
Base.length(::Hole) = 0

"""
	Base.isless(rn₁::AbstractRuleNode, rn₂::AbstractRuleNode)::Bool

Compares two [`RuleNode`](@ref)s. Returns true if the left [`RuleNode`](@ref) is less than the right [`RuleNode`](@ref).
Order is determined from the index of the [`RuleNode`](@ref)s. 
If both [`RuleNode`](@ref)s have the same index, a depth-first search is 
performed in both [`RuleNode`](@ref)s until nodes with a different index
are found.
"""
Base.isless(rn₁::AbstractRuleNode, rn₂::AbstractRuleNode)::Bool = _rulenode_compare(rn₁, rn₂) == -1


function _rulenode_compare(rn₁::RuleNode, rn₂::RuleNode)::Int
	# Helper function for Base.isless
	if rn₁.ind == rn₂.ind
		for (c₁, c₂) ∈ zip(rn₁.children, rn₂.children)
			comparison = _rulenode_compare(c₁, c₂)
			if comparison ≠ 0
				return comparison
			end
		end
		return 0
	else
		return rn₁.ind < rn₂.ind ? -1 : 1
	end
end

_rulenode_compare(::Hole, ::RuleNode) = -1
_rulenode_compare(::RuleNode, ::Hole) = 1
_rulenode_compare(::Hole, ::Hole) = 0


"""
	depth(root::RuleNode)::Int

Return the depth of the [`AbstractRuleNode`](@ref) tree rooted at root.
Holes don't count towards the depth.
"""
function depth(root::RuleNode)::Int
	retval = 1
	for c in root.children
	    retval = max(retval, depth(c)+1)
	end
	return retval
end

depth(::Hole) = 0


"""
	node_depth(root::AbstractRuleNode, node::AbstractRuleNode)::Int

Return the depth of `node` for an [`AbstractRuleNode`](@ref) tree rooted at `root`.
Depth is `1` when `root == node`.

!!! warning
	`node` must be a subtree of `root` in order for this function to work.
"""
function node_depth(root::AbstractRuleNode, node::AbstractRuleNode)::Int
	root ≡ node && return 1
	root isa Hole && return 0
	for c in root.children
	    d = node_depth(c, node)
	    d > 0 && (return d+1)
	end
	return 0
end
