# =======================================
# macros.jl -- helper macros for grammars
# =======================================

using MacroTools: @capture, postwalk, rmlines

"""
    @grammar startrule::Symbol rules

    Generate a function to parse the given grammar.

    See documentation (to be written!) about its usage.
"""
macro grammar(startrule, expr)

    # the first thing we have to do is work out how
    # PikaParser was called in the current context --
    # whether it was a simple "import PikaParser" or
    # "import PikaParser as P" or something more exotic.
    # So, we have to reflect into the namespace of the
    # calling module, and look for ourselves in that list.

    # so, first off: get the names in the calling module
    # namespace, and filter out the non-module names with
    # an @eval in the caller's context. We don't know anything
    # about this context -- e.g. there could be some variables
    # declared but not defined -- so we need to wrap this test
    # in a try/catch.
    localnames = names(__module__, imported=true)
    localmods  = [name for name in localnames
                    if @eval(__module__,
                        try
                            $name isa Module
                        catch e
                            false
                        end)]

    # now that we have a candidate list, we can finally look for
    # ourselves by evaluating nameof() in caller context.
    # This gives us the symbol we need to prefix our calls with.
    P = [mod for mod in localmods
            if @eval(__module__, nameof($mod) == :PikaParser)][1]
    
    # now we define our substitutions against that symbol.
    pika_syms = Dict(
        :satisfy            => :($P.satisfy           ),
        :scan               => :($P.scan              ),
        :token              => :($P.token             ),
        :tokens             => :($P.tokens            ),
        :epsilon            => :($P.epsilon           ),
        :fail               => :($P.fail              ),
        :seq                => :($P.seq               ),
        :first              => :($P.first             ),
        :not_followed_by    => :($P.not_followed_by   ),
        :followed_by        => :($P.followed_by       ),
        :some               => :($P.some              ),
        :many               => :($P.many              ),
        :tie                => :($P.tie               ),
        :precedence_cascade => :($P.precedence_cascade),
    )

    rules = postwalk(rmlines, expr)

    # rewrite rules for regular expression syntax.
    rules = postwalk(rules) do e

        # match the regex string, and pull any tail arguments.
        @capture(e, @r_str regexstr__) || return e
        regex, args = length(regexstr) > 1 ? (regexstr[1], regexstr[2]) :
                                             (regexstr[1], nothing)

        # force a '^' at the beginning to fend off maximal munch,
        # then compile the regex.
        regex = regex[1] == '^' ? regex : "^" * regex
        r = isnothing(args) ? Regex(regex) : Regex(regex, args)

        @gensym x matched
        return quote
            scan($x -> begin
                $matched = match($r, $x)
                isnothing($matched) && return 0
                return length($matched.match)
            end) 
        end
    end

    # add maybe() tags.
    rules = postwalk(rules) do e
        @capture(e, maybe(expr__)) || return e
        return quote first($(expr...), epsilon) end
    end

    # walk the expression tree, add PikaParser qualification
    rules = postwalk(rules) do e
        e isa Symbol || return e
        return get(pika_syms, e, e)
    end

    # make a lambda expression that parses the input string
    # according to the provided grammar. Remember to tag the
    # PikaParser qualification so the generated code is sane.
    @gensym x y
    quote
        $x ->
            $P.parse(
                $P.make_grammar(
                    [$(startrule)],
                    $P.flatten(Dict($rules), Char)
                ),
            $x)
    end |> esc
end

macro evaluate(top, m, v, exprs)

    # see the definition of @grammar for an explanation
    localnames = names(__module__, imported=true)
    localmods  = [name for name in localnames
                    if @eval(__module__,
                        try
                            $name isa Module
                        catch e
                            false
                        end)]
    P = [mod for mod in localmods
            if @eval(__module__, nameof($mod) == :PikaParser)][1]

    # gather our rules (in the form rule => value)
    # as "m.rule == rule ? value : v" form.
    rules = Expr[]
    postwalk(exprs) do e
        @capture(e, rule_quote => value_) || return e
        push!(rules, quote 
            $(m).rule == $rule ? begin $value end :
                (length($v) > 1 ? $(v) : length(v) == 1 ? $(v)[1] : nothing)
        end)
        return e
    end

    # rewrite the AST so that the "else" node
    # now points to the next expression.
    reducedrules = reduce(reverse(rules)) do r1, r2
        r2.args[2].args[3] = r1
        r2
    end

    # generate our evaluator function with fold
    # mapping to the reduced ruleset
    @gensym parsed
    return quote
        $parsed -> $P.traverse_match($parsed,
            $P.find_match_at!($parsed, $top, 1),
            fold = function ($m, _, $v)
                $(reducedrules)
            end
        )
    end |> esc
end
