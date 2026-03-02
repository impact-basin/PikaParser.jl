@testset "Helper macros" begin

    identifiers = P.@syntax :top begin
        :ws    => first(satisfy(isspace), epsilon),
        :ident => r"[a-z_]+[a-z0-9_]*"i,
        :decl  => seq(:ident, :ws),
        :top   => some(:decl)
    end
    p = identifiers("foo Bar bA9Z QUx")

    m = P.find_match_at!(p, :top, 1)
    @test m != 0
    folded = P.traverse_match(
        p,
        m,
        fold = (m, p, v) ->
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

@testset "Maybe" begin

    g = P.@syntax :top begin
        :ws    => some(satisfy(isspace)),
        :ident => seq(r"[a-zA-Z_]", r"[a-zA-Z0-9_]*"),
        :digit => r"[0-9]+",
        :expr  => seq(:ident, :ws, maybe(:digit)),
        :exws  => seq(maybe(:ws), :expr),
        :top   => some(:exws)
    end

    a = P.@semantics :top m v begin
        :ident => Symbol(m.view)
        :digit => parse(Int, m.view)
        :expr  => begin
            v[3]  == [] ? v[1] => nothing :
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
