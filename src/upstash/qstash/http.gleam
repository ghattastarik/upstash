import gleam/int
import gleam/list
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/result
import gleam/dynamic/decode
import gleam/json

pub type HttpMethod {
  Post
  Get
  Put
  Patch
  Delete
}

pub type DispatchResult {
  UrlResult(
    message_id: String,
    // deduplicated: Bool,
  )
  GroupResult(List(GroupResultItem))
  ErrorResult(
    error: String,
  )
}

pub type GroupResultItem {
  GroupResultItem(
    message_id: String,
    deduplicated: Bool,
    url: String
  )
}

pub type DispatchError {
  UrlError
  HttpError(httpc.HttpError)
  DecodeError(json.DecodeError)
}

pub fn method_to_string(method: HttpMethod) -> String {
  case method {
    Post -> "post"
    Get -> "get"
    Put -> "put"
    Patch -> "patch"
    Delete -> "delete"
  }
}

pub fn dispatch(
  msg body: String,
  to url: String,
  with headers: List(#(String, String)),
  auth token: String
) -> Result(DispatchResult, DispatchError) {
  use req <- result.try(request.to(url) |> result.map_error(fn(_) { UrlError }))
  let req =
    req
    |> merge_headers(headers)
    |> request.set_header("authorization", "Bearer " <> token)
    |> request.set_method(http.Post)
    // |> request.set_scheme(http.Https)
    |> request.set_body(body)
  use resp <- result.try(httpc.send(req) |> result.map_error(HttpError))
  let content_type = response.get_header(resp, "content-type")
  let assert Ok("application/json") = content_type

  let decoder =
    case resp.status {
      200 | 201 -> decode.one_of(url_result_decoder(), or: [group_result_decoder()])
      400 | 401 -> error_result_decoder()
      code -> {
        let msg = "Unknown response status: " <> code |> int.to_string
        panic as msg
      }
    }

  json.parse(resp.body, decoder)
  |> result.map_error(DecodeError)
}

fn merge_headers(req: request.Request(a), headers: List(#(String, String))) -> request.Request(a) {
  req
  |> list.fold(headers, _, fn(request, tuple) {
    let #(key, value) = tuple
    request.set_header(request, key, value)
  })
}

fn url_result_decoder() {
  use message_id <- decode.field("messageId", decode.string)
  // use deduplicated <- decode.field("deduplicated", decode.bool)
  decode.success(UrlResult(message_id:))
}

fn group_result_item_decoder() {
  use url <- decode.field("url", decode.string)
  use message_id <- decode.field("messageId", decode.string)
  use deduplicated <- decode.field("deduplicated", decode.bool)
  decode.success(GroupResultItem(message_id:, deduplicated:, url:))
}

fn group_result_decoder() {
  decode.list(group_result_item_decoder())
  |> decode.map(fn(list) { GroupResult(list) })
}

fn error_result_decoder() {
  use error <- decode.field("error", decode.string)
  decode.success(ErrorResult(error:))
}
