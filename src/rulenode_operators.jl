"""
Returns all rules of a specific type used in a RuleNode.
"""
function rulesoftype(node::RuleNode, ruleset::Set{Int})
	retval = Set()

	if node.ind in ruleset
		union!(retval, [node.ind])
	end

	if isempty(node.children)
		return retval
	else
		for child in node.children
			union!(retval, rulesoftype(child, ruleset))
		end

		return retval
	end
end

rulesoftype(::Hole, ::Set{Int}) = Set()
rulesoftype(node::RuleNode, grammar::Grammar, ruletype::Symbol) = rulesoftype(node, Set(grammar[ruletype]))
rulesoftype(::Hole, ::Grammar, ::Symbol) = Set()


"""
Returns all rules of a specific type used in a RuleNode but not in the ignoreNode.
"""
function rulesoftype(node::RuleNode, ruleset::Set{Int}, ignoreNode::RuleNode)
	retval = Set()

	if node == ignoreNode
		return retval
	end

	if node.ind in ruleset
		union!(retval, [node.ind])
	end

	if isempty(node.children)
		return retval
	else
		for child in node.children
			union!(retval, rulesoftype(child, ruleset))
		end

		return retval
	end
end
rulesoftype(::Hole, ::Set{Int}, ::RuleNode) = Set()

rulesoftype(node::RuleNode, grammar::Grammar, ruletype::Symbol, ignoreNode::RuleNode) = rulesoftype(node, Set(grammar[ruletype]), ignoreNode)
rulesoftype(::Hole, ::Grammar, ::Symbol, ::RuleNode) = Set()

"""
Replace a node in expr, specified by path, with new_expr.
Path is a sequence of child indices, starting from the node.
"""
function swap_node(expr::AbstractRuleNode, new_expr::AbstractRuleNode, path::Vector{Int})
	if length(path) == 1
		expr.children[path[begin]] = new_expr
	else
		swap_node(expr.children[path[begin]], new_expr, path[2:end])
	end
end


"""
Replace child i of a node, a part of larger expr, with new_expr.
"""
function swap_node(expr::RuleNode, node::RuleNode, child_index::Int, new_expr::RuleNode)
	if expr == node 
		node.children[child_index] = new_expr
	else
		for child ∈ expr.children
			swap_node(child, node, child_index, new_expr)
		end
	end
end


"""
Extract derivation sequence from path (sequence of child indices).
If the path is deeper than the deepest node, it returns what it has.
"""
function get_rulesequence(node::RuleNode, path::Vector{Int})
	if node.ind == 0 # sign for empty node 
		return Vector{Int}()
	elseif isempty(node.children) # no childnen, nowehere to follow the path; still return the index
		return [node.ind]
	elseif isempty(path)
		return [node.ind]
	elseif isassigned(path, 2)
		# at least two items are left in the path
		# need to access the child with get because it can happen that the child is not yet built
		return append!([node.ind], get_rulesequence(get(node.children, path[begin], RuleNode(0)), path[2:end]))
	else
		# if only one item left in the path
		# need to access the child with get because it can happen that the child is not yet built
		return append!([node.ind], get_rulesequence(get(node.children, path[begin], RuleNode(0)), Vector{Int}()))
	end
end

get_rulesequence(::Hole, ::Vector{Int}) = Vector{Int}()

"""
Extracts rules in the left subtree defined by the path.
"""
function rulesonleft(expr::RuleNode, path::Vector{Int})
	if isempty(expr.children)
		# if the encoutered node is terminal or non-expanded non-terminal, return node id
		Set{Int}(expr.ind)
	elseif isempty(path)
		# if path is empty, collect the entire subtree
		ruleset = Set{Int}(expr.ind)
		for ch in expr.children
			union!(ruleset, rulesonleft(ch, Vector{Int}()))
		end
		return ruleset 
	elseif length(path) == 1
		# if there is only one element left in the path, collect all children except the one indicated in the path
		ruleset = Set{Int}(expr.ind)
		for i in 1:path[begin]-1
			union!(ruleset, rulesonleft(expr.children[i], Vector{Int}()))
		end
		return ruleset 
	else
		# collect all subtrees up to the child indexed in the path
		ruleset = Set{Int}(expr.ind)
		for i in 1:path[begin]-1
			union!(ruleset, rulesonleft(expr.children[i], Vector{Int}()))
		end
		union!(ruleset, rulesonleft(expr.children[path[begin]], path[2:end]))
		return ruleset 
	end
end

rulesonleft(::Hole, ::Vector{Int}) = Set{Int}()


"""
Converts a rulenode into a julia expression. 
The returned expression can be evaluated with Julia semantics using eval().
"""
function rulenode2expr(rulenode::RuleNode, grammar::Grammar)
	root = (rulenode._val !== nothing) ?
		rulenode._val : deepcopy(grammar.rules[rulenode.ind])
	if !grammar.isterminal[rulenode.ind] # not terminal
		root,_ = _rulenode2expr(root, rulenode, grammar)
	end
	return root
end


function _rulenode2expr(expr::Expr, rulenode::RuleNode, grammar::Grammar, j=0)
	for (k,arg) in enumerate(expr.args)
		if isa(arg, Expr)
			expr.args[k],j = _rulenode2expr(arg, rulenode, grammar, j)
		elseif haskey(grammar.bytype, arg)
			child = rulenode.children[j+=1]
			expr.args[k] = (child._val !== nothing) ?
			child._val : deepcopy(grammar.rules[child.ind])
			if !isterminal(grammar, child)
				expr.args[k],_ = _rulenode2expr(expr.args[k], child, grammar, 0)
			end
		end
	end
	return expr, j
end


function _rulenode2expr(typ::Symbol, rulenode::RuleNode, grammar::Grammar, j=0)
	retval = typ
		if haskey(grammar.bytype, typ)
			child = rulenode.children[1]
			retval = (child._val !== nothing) ?
				child._val : deepcopy(grammar.rules[child.ind])
			if !grammar.isterminal[child.ind]
				retval,_ = _rulenode2expr(retval, child, grammar, 0)
			end
		end
	retval, j
end


"""
Calculates the log probability associated with a rulenode in a probabilistic grammar.
"""
function rulenode_log_probability(node::RuleNode, grammar::Grammar)
	log_probability(grammar, node.ind) + sum((rulenode_log_probability(c, grammar) for c ∈ node.children), init=1)
end

rulenode_log_probability(::Hole, ::Grammar) = 1


"""
Returns true if the expression given by the node is complete expression, i.e., all leaves are terminal symbols
"""
function iscomplete(grammar::Grammar, node::RuleNode) 
	if isterminal(grammar, node)
		return true
	elseif isempty(node.children)
		# if not terminal but has children
		return false
	else
		return all([iscomplete(grammar, c) for c in node.children])
	end
end

iscomplete(grammar::Grammar, ::Hole) = false


"""
Returns the return type in the production rule used by node.
"""
return_type(grammar::Grammar, node::RuleNode) = grammar.types[node.ind]


"""
Returns the list of child types in the production rule used by node.
"""
child_types(grammar::Grammar, node::RuleNode) = grammar.childtypes[node.ind]


"""
Returns true if the production rule used by node is terminal, i.e., does not contain any nonterminal symbols.
"""
isterminal(grammar::Grammar, node::RuleNode) = grammar.isterminal[node.ind]


"""
Returns the number of children in the production rule used by node.
"""
nchildren(grammar::Grammar, node::RuleNode) = length(child_types(grammar, node))


"""
Returns true if the rule used by the node represents a variable.
"""
isvariable(grammar::Grammar, node::RuleNode) = grammar.isterminal[node.ind] && grammar.rules[node.ind] isa Symbol

isvariable(grammar::Grammar, ind::Int) = grammar.isterminal[ind] && grammar.rules[ind] isa Symbol


"""
Returns true if the tree rooted at node contains at least one node at depth less than maxdepth
with the given return type.
"""
function contains_returntype(node::RuleNode, grammar::Grammar, sym::Symbol, maxdepth::Int=typemax(Int))
    maxdepth < 1 && return false
    if return_type(grammar, node) == sym
        return true
    end
    for c in node.children
        if contains_returntype(c, grammar, sym, maxdepth-1)
            return true
        end
    end
    return false
end


"""
Checks if a rulenode tree contains a hole.
"""
contains_hole(rn::RuleNode) = any(containsHole(c) for c ∈ rn.children)
contains_hole(hole::Hole) = true


function Base.display(rulenode::RuleNode, grammar::Grammar)
	root = rulenode2expr(rulenode, grammar)
	if isa(root, Expr)
	    walk_tree(root)
	else
	    root
	end
end
