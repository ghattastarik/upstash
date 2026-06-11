import gleam/bit_array
import gleam/result
import gleam/option.{type Option, Some, None}
import gleam/http/request
import gleam/dynamic/decode
import gleam/crypto
import gwt

const expected_issuer = "Upstash"

pub type ReceiverConfig {
  ReceiverConfig(
    current_signing_key: String,
    next_signing_key: String,
    url: Option(String)
  )
}

pub type VerifyRequest {
  VerifyRequest(
    signature: String,
    body: String,
  )
}

pub type VerifyError {
  SignatureMissing
  InvalidSignature
  InvalidClaims
  WrongSubject
}

pub fn config(
  current_signing_key: String,
  next_signing_key: String
) -> ReceiverConfig {
  ReceiverConfig(
    current_signing_key:,
    next_signing_key:,
    url: None
  )
}

pub fn set_url(cfg: ReceiverConfig, url: String) -> ReceiverConfig {
  ReceiverConfig(..cfg, url: Some(url))
}

pub fn verify(req: request.Request(String), cfg: ReceiverConfig) -> Result(Nil, VerifyError) {
  use req <- result.try(request_to_verify_request(req))
  echo req as "VerifyRequest"
  use jwt <- result.try(
    result.lazy_or(
      gwt.from_signed_string(req.signature, cfg.current_signing_key),
      fn () { gwt.from_signed_string(req.signature, cfg.next_signing_key) }
    )
    |> result.map_error(
      fn (err) {
        case err {
          _ -> InvalidClaims
        }
      }
    )
  )
  echo jwt as "Parsed jwt with sig"

  use <- verify_issuer(jwt)
  use <- verify_subject(jwt, cfg)
  verify_body(jwt, req.body)
}

fn request_to_verify_request(req: request.Request(String)) -> Result(VerifyRequest, VerifyError) {
  use signature <- result.try(
    request.get_header(req, "upstash-signature")
    |> result.replace_error(SignatureMissing)
  )
  let body = req.body
  Ok(VerifyRequest(signature:, body:))
}

fn verify_issuer(jwt: gwt.Jwt(a), next: fn () -> Result(Nil, VerifyError)) -> Result(Nil, VerifyError) {
  use value <- result.try(
    gwt.get_issuer(jwt)
    |> result.replace_error(InvalidClaims)
  )
  case value == expected_issuer {
    True -> next()
    False -> {
      echo "Wrong issuer"
      Error(WrongSubject)
    }
  }
}

fn verify_subject(
  jwt: gwt.Jwt(a),
  cfg: ReceiverConfig,
  next: fn () -> Result(Nil, VerifyError)
) -> Result(Nil, VerifyError) {
  case cfg.url {
    None -> next()
    Some(expected) -> {
      use value <- result.try(
        gwt.get_subject(jwt)
        |> result.replace_error(InvalidClaims)
      )
      case value == expected {
        False -> {
          echo "Wrong subject"
          Error(InvalidClaims)
        }
        True -> next()
      }
    }
  }
}

fn verify_body(jwt: gwt.Jwt(a), body: String) -> Result(Nil, VerifyError) {
  use value <- result.try(
    gwt.get_payload_claim(jwt, "body", decode.string)
    |> result.map(bit_array.from_string)
    |> result.replace_error(InvalidClaims)
  )
  echo value as "Payload body as bit array"

  let expected =
    body
    |> echo as "Body to verify against"
    |> bit_array.from_string
    |> crypto.hash(crypto.Sha256, _)
    |> bit_array.base64_url_encode(True)
    |> echo as "Hashed body"
    |> bit_array.from_string
    |> echo as "Hashed body as bit array"

  case crypto.secure_compare(value, expected) {
    True -> Ok(Nil)
    False -> Error(InvalidClaims)
  }
}
