export CKKSParams, FixedRational

################################################################################
#                        CKKS Scheme definition
################################################################################

struct CKKSParams <: SHEShemeParams
    # The Cypertext ring over which operations are performed
    ℛ
    # The big ring used during multiplication
    ℛbig
    relin_window
    σ
end
scheme_name(p::Type{CKKSParams}) = "CKKS"

# From the RLWE perspective, ℛ is both the plain and ciphertext. The encoder
# takes care of the conversion to/from complex numbers.
ℛ_plain(p::CKKSParams) = p.ℛ
ℛ_cipher(p::CKKSParams) = p.ℛ

π⁻¹(params::CKKSParams, plaintext) = params.ℛ(plaintext)
π(params::CKKSParams, b) = b

𝒩(params::CKKSParams) = RingSampler(params.ℛ, DiscreteNormal(0, params.σ))
𝒢(params::CKKSParams) = RingSampler(params.ℛ, DiscreteNormal(0, params.σ))

mul_expand(params::CKKSParams, c::CipherText) = map(c->switch(params.ℛbig, c), c.cs)
function mul_contract(params::CKKSParams, c)
    @fields_as_locals params::CKKSParams
    map(c) do e
        switch(ℛ, e)
    end
end

################################################################################
#                        CKKS Scheme definition
################################################################################

"""
    FixedRational{T<:Integer, den} <: Real
Rational number type, with numerator of type T and fixed denominator `den`.
"""
struct FixedRational{T, denom}
    x::T
    Base.reinterpret(::Type{FixedRational{T, denom}}, x::T) where {T,denom} =
        new{T, denom}(x)
    function FixedRational{T, denom}(x::Real) where {T, denom}
        n = round(BigInt, big(x)*denom)
        if n < 0
            n = modulus(T) + n
        end
        new{T, denom}(convert(T, n))
    end
end

function Base.convert(::Type{Float64}, fr::FixedRational{T, denom}) where {T, denom}
    n = convert(Integer, fr.x)
    if n > div(modulus(T), 2)
        n = n - modulus(T)
    end
    Float64(n/denom)
end

function Base.show(io::IO, fr::FixedRational{<:Any, denom}) where {denom}
    print(io, convert(Float64, fr))
end
