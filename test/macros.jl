@testset "Helper macros" begin

    identifiers = P.@syntax :top begin
        :ws    => first(satisfy(isspace), epsilon)
        :ident => r"[a-z_]+[a-z0-9_]*"i
        :decl  => seq(:ident, :ws)
        :top   => some(:decl)
    end
    p = identifiers("foo Bar bA9Z QUx")

    m = P.find_match_at!(p, :top, 1)
    @test m != 0
    folded = P.traverse_match(
        p,
        m,
        fold = (m, _, v) ->
            m.rule == :ident ? Symbol(m.view) :
            m.rule == :decl  ? v[1]           :
            m.rule == :top   ? v              :
            nothing
    )

    @test all(typeof.(folded) .== Symbol)
    @test folded[1] == :foo
    @test folded[2] == :Bar
    @test folded[3] == :bA9Z
    @test folded[4] == :QUx

    testsemantics = P.@semantics :top
    @test testsemantics(p) == 
        (:top => Any[
            :decl => Any[:ident => "foo",  :ws => Any[Symbol("ws-1") => " "]],
            :decl => Any[:ident => "Bar",  :ws => Any[Symbol("ws-1") => " "]],
            :decl => Any[:ident => "bA9Z", :ws => Any[Symbol("ws-1") => " "]],
            :decl => Any[:ident => "QUx",  :ws => ""]
         ])

    idents_to_syms = P.@semantics :top m v begin
        :ident => Symbol(m.view)
        :decl  => v[1]
        :top   => v
    end

    ids = identifiers("foo Bar bA9Z QUx") |> idents_to_syms
    @test all(folded .== ids)
end

x = @macroexpand Threads.@threads for i=1:10
    @show i
end

@testset "Helper macros with local symbols " begin
    function test_local_scoping()

        myisdigit(x) = isdigit(x)
        myisspace(x) = isspace(x)

        syntax_exprs = @macroexpand P.@syntax :top begin
            :ws     => many(satisfy(myisspace))
            :number => some(:digit => satisfy(myisdigit))
            :top    => seq(:ws, :number)
        end true

        @test :(:make_grammar) ==
            syntax_exprs.args[2].args[2].args[2].
                         args[1].args[2]

        syntax = P.@syntax :top begin
            :ws     => many(satisfy(myisspace))
            :number => some(:digit => satisfy(myisdigit))
            :plus   => seq(:pexpr, :ws, token('+'), :ws, :pexpr, :ws)
            :minus  => seq(:pexpr, :ws, token('-'), :ws, :pexpr, :ws)
            :times  => seq(:pexpr, :ws, token('*'), :ws, :pexpr, :ws)
            :divby  => seq(:pexpr, :ws, token('/'), :ws, :pexpr, :ws)
            :paren  => seq(token('('), :ws, :expr, :ws, token(')'), :ws)
            :expr   => first(:times, :divby, :plus, :minus, :number)
            :pexpr  => first(:paren, :expr)
            :top    => seq(:ws, :pexpr)
        end true

        semantics = @P.semantics :top m v begin
            :number => parse(Int, m.view)
            :expr   => v[1]
            :plus   => v[1] + v[5]
            :minus  => v[1] - v[5]
            :times  => v[1] * v[5]
            :divby  => v[1] / v[5]
            :paren  => v[3]
            :expr   => v[1]
            :pexpr  => v[1]
            :top    => v[2]
        end

        return x -> x |> syntax |> semantics
    end

    calc = test_local_scoping()

    @test calc("3 + 2 + 8") == 13
    @test calc("3 * (2 + 16)") == 54
    @test calc("3 + 5 * (2 + 16)") == 93
end
