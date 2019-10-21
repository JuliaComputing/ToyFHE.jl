using GaloisFields
using Nemo
using Hecke

# A cache for the computed isomorphisms between the canonical representation
# of the finite field 𝕂 and each of the plaintext slots 𝕃ᵢ = 𝔽p/fᵢ.
struct ExplicitIsomorphisms
    # The type from GaloisFields.jl that'll represent our plaintext (for k=1)
    # The ring from Nemo.jl that represents our plaintext (for k > 1)
    𝔽pn::Union{Type{<:GaloisFields.AbstractExtensionField}, AbstractAlgebra.Generic.ResRing{nmod_poly}}
    d::Int
    # crt_env(factor(f))
    ce::crt_env
    # Isomorphisms between finite field extensions are uniquly defined by
    # where they send the generator of the field.
    σ::Vector # σ: 𝕂 -> 𝕃ᵢ
    σ⁻¹::Vector # σ⁻¹  𝕃ᵢ -> 𝕂
end

struct SchemeParameterError
    msg::String
end

function construct_isomorphisms(f)
    ℤpkx = parent(f)
    ℤx, x = PolynomialRing(Nemo.ZZ, "x")

    pk = modulus(ℤpkx)
    pkfact = Primes.factor(pk)

    length(pkfact) == 1 || throw(SchemeParameterError("PolyCRTEncoding only supported for prime or prime power plaintext moduli. Got `$pkfact`."))
    (p, k) = collect(pkfact)[1]

    factors = ℤpkx.(collect(keys(Hecke.factor_mod_pk(lift(ℤx, f), Int(p), k))))

    l = length(factors)
    d = div(degree(f), l)

    # For k = 1, we use the GaloisField type from GaloisFields.jl since it's a bit friendlier
    # Julia users. Construct that type now.
    if k == 1
        𝔽, β = GaloisField(l, d, :β)
    else
        # TODO: Should we instead lift the conway polynomial of the underlying
        # finite field?
        𝔽 = ResidueRing(ℤpkx, factors[1])
        β = Nemo.gen(ℤpkx)
    end

    # TODO: Which function in Nemo/hecke is this?
    function evaluate_at_map(c, map)
        sum(coeff(c, i) * map^i for i in 0:d)
    end

    if k == 1
        # G is the minimum polynomial of F (generally a Conway polynomial), i.e.
        # 𝔽 = 𝔽p[β]/G(β)
        G = sum(c.n * x^i for (i, c) in zip(0:GaloisFields.n(GaloisField(2, 3)[1]), GaloisFields.minpoly(GaloisField(2, 3)[1])))

        σ = map(factors) do factor
            rts = Nemo.roots(G, FiniteField(ℤpkx(factor), "z")[1])
            # TODO: Does nemo define a canonical order on these that we could reuse?
            #       Does `roots` return the roots in a canonical order?
            rt = first(sort(rts, by=r->reverse([coeff(r, i) for i = 0:degree(factor)])))
            # TODO: Shouldn't there be some sort of better function for this
            evaluate_at_map(rt, x)
        end

        σ⁻¹ = map(enumerate(factors)) do (i, factor)
            F, z = FiniteField(ℤpkx(G), "z")
            rts = Nemo.roots(Nemo.lift(ℤx, factor), F)
            # Find whichever of these is the inverse of the isomorphism we picked above
            # TODO: Is there a better way that just computes both at once?
            first(rt for rt in rts if evaluate_at_map(σ[i], rt) == z)
        end
    else
        σ = σ⁻¹ = [function (x)
            if degree(isa(x,nmod_poly) ? x : data(x)) > 0
                error("Not yet supported")
            end
            x
        end for _ = 1:l]
    end

    ExplicitIsomorphisms(𝔽, d, crt_env(factors), σ, σ⁻¹)
end

function lookup_isomorphisms(f)
    construct_isomorphisms(f)
end

struct PolyCRTEncoding{T} <: AbstractVector{T}
    # TODO: Should this just be looked up by type?
    isos::ExplicitIsomorphisms
    slots::Vector
end
Base.length(a::PolyCRTEncoding) = length(a.slots)
Base.size(a::PolyCRTEncoding) = (length(a),)
Base.getindex(a::PolyCRTEncoding, idxs...) = getindex(a.slots, idxs...)
Base.setindex!(a::PolyCRTEncoding, v, idxs...) = setindex!(a.slots, a.isos.𝔽pn(v), idxs...)

function PolyCRTEncoding(r::R) where R<:AbstractAlgebra.Generic.Res{nmod_poly}
    isos = lookup_isomorphisms(modulus(r))

    # And backwards...
    decoded = Hecke.crt_inv(data(r), isos.ce)

    function evaluate_at_map(c, map)
        sum(coeff(c, i) * map^i for i in 0:isos.d)
    end
    evaluate_at_map(c, map::Function) = map(c)

    eT = typeof(isos.𝔽pn(0))
    # Back to the representation wrt G
    unmapped = map(zip(decoded, isos.σ⁻¹)) do (d, σ⁻¹)
        r = evaluate_at_map(d, σ⁻¹)
        if isa(isos.𝔽pn, Type) && isos.𝔽pn <: GaloisFields.AbstractExtensionField
            r = evaluate_at_map(r, GaloisFields.gen(isos.𝔽pn))
        end
        isos.𝔽pn(r)
    end

    PolyCRTEncoding{eT}(isos, unmapped)
end

function (ℛ::AbstractAlgebra.Generic.ResRing{nmod_poly})(e::PolyCRTEncoding)
    ℤpx = base_ring(ℛ)
    mapped = map(zip(e.slots, e.isos.σ)) do (plain, σ)
        if isa(plain, GaloisFields.AbstractExtensionField)
            ℤpx(sum(c.n*σ^i for (i,c) in zip(0:GaloisFields.n(e.isos.𝔽pn), GaloisFields.expansion(plain))))
        else
            data(σ(plain))
        end
    end
    ℛ(Nemo.crt(mapped, e.isos.ce))
end
Base.convert(ℛ::AbstractAlgebra.Generic.ResRing{nmod_poly}, e::PolyCRTEncoding) = ℛ(e)
