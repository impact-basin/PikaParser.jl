@testset "Helper macros" begin

    identifiers = P.@grammar :top begin
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
end

