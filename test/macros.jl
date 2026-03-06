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

    idents_to_syms = P.@semantics :top m v begin
        :ident => Symbol(m.view)
        :decl  => v[1]
    end

    ids = identifiers("foo Bar bA9Z QUx") |> idents_to_syms
    @test all(folded .== ids)
end

# this declaration must happen outside of the local
# scope created by testset.
myisdigit(x) = isdigit(x)
myisspace(x) = isspace(x)

@testset "Calculator" begin

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
    end

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

    calc = x -> x |> syntax |> semantics

    @test calc("3 + 2 + 8") == 13
    @test calc("3 * (2 + 16)") == 54
    @test calc("3 + 5 * (2 + 16)") == 93
end

@testset "Maybe" begin

    g = P.@syntax :top begin
        :ws    => some(satisfy(isspace))
        :ident => seq(r"[a-zA-Z_]", r"[a-zA-Z0-9_]*")
        :digit => r"[0-9]+",
        :expr  => seq(:ident, :ws, maybe(:digit))
        :exws  => seq(maybe(:ws), :expr)
        :top   => some(:exws)
    end

    a = P.@semantics :top m v begin
        :ident => Symbol(m.view)
        :digit => parse(Int, m.view)
        :expr  => begin
            v[3]  == "" ? v[1] => nothing :
                          v[1] => v[3][1]
        end
        :exws  => v[2]
        :top   => v
    end

    parsed = g("foo_bar 1 bar baz 23 qux 45") |> a
    @test parsed[1] == (:foo_bar => 1)
    @test parsed[2] == (:bar     => nothing)
    @test parsed[3] == (:baz     => 23)
    @test parsed[4] == (:qux     => 45)

end
