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
        @capture(e, id_ => @r_str regexstr__) || return e
        regex, args = length(regexstr) > 1 ? (regexstr[1], regexstr[2]) :
                                             (regexstr[1], nothing)

        # force a '^' at the beginning to fend off maximal munch
        regex = regex[1] == '^' ? regex : "^" * regex

        # finally, compile the regex, and rewrite the node.
        r = isnothing(args) ? Regex(regex) : Regex(regex, args)
        @gensym x matched
        return quote
            $id => scan() do $x
                $matched = match($r, $x)
                isnothing($matched) && return 0
                return length($matched.match)
            end
        end
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
