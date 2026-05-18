import gleam/json.{type Json}
import gleam/string
import gleam/bool
import gleam/dict
import gleam/list
import gleam/result
import gleam/option.{type Option, None, Some}
import envoy
import upstash/qstash/http.{type HttpMethod}

const base_url = "https://qstash.upstash.io"

pub opaque type ClientConfig {
  ClientConfig(
    base_url: String,
    token: String,
    retry: Option(RetryConfig),
    // headers: String,
  )
}

pub opaque type PublishRequest(body, dest) {
  PublishRequest(
    body: body,
    url: Option(String),
    url_group: Option(String),
    headers: List(#(String, String)),
    // delay:,
    // not_before:,
    // deduplication_id:,
    content_based_deduplication: Bool,
    // retries:,
    // retry_delay:,
    // failure_callbacks:,
    method: HttpMethod,
    // timeout:,
    // flowcontrol:,
    // label:,
    // api:,
    // callback:,
  )
}

pub type MissingDestination
pub type Ready

pub opaque type RetryConfig {
  RetryConfig(
    retries: Int,
    backoff: fn (Int) -> Int,
  )
}

pub fn configure(token: String) {
  let base_url =
    envoy.get("QSTASH_URL")
    |> result.unwrap(base_url)
  ClientConfig(base_url:, token:, retry: None)
}

// Creates a new PublishRequest message.
// To use with functions to or to_group, with_headers, returning, retries and finally send
pub fn message(body: body) -> PublishRequest(body, MissingDestination) {
  PublishRequest(
    body:,
    headers: [],
    url: None,
    url_group: None,
    content_based_deduplication: False,
    method: http.Post,
  )
}

// destination url (must be publicly available)
pub fn to(
  req: PublishRequest(body, MissingDestination),
  url: String
) -> PublishRequest(body, Ready) {
  PublishRequest(..req, url: Some(url))
}

pub fn with_headers(
  req: PublishRequest(body, dest),
  headers: List(#(String, String))
) -> PublishRequest(body, dest) {
  PublishRequest(..req, headers: list.append(req.headers, headers))
}

pub fn retries(
  req: PublishRequest(body, dest),
  max count: Int,
  with backoff: fn (Int) -> Int
) -> PublishRequest(body, dest) {
  todo
}

// using urlgroups or fanout
pub fn to_group(
  req: PublishRequest(body, MissingDestination),
  group: String
) -> PublishRequest(body, Ready) {
  PublishRequest(..req, url_group: Some(group))
}

pub fn send(
  req: PublishRequest(String, Ready),
  using cfg: ClientConfig
) {
  let path = "/v2/publish/"
  let assert Some(dest) = option.or(req.url, req.url_group)
  let url = cfg.base_url <> path <> dest
  let headers = prepare_headers(req)

  http.dispatch(req.body, url, headers, cfg.token)
  // case req.url, req.url_group {
  //   Some(url), _ -> url
  //   _, Some(url_group) -> url_group
  //   _, _ -> panic
  // }
}

// wrapper around publish that serializes body and adds content-type header.
pub fn message_json(body: Json) -> PublishRequest(String, MissingDestination) {
  PublishRequest(
    body: body |> json.to_string,
    headers: [#("content-type", "application/json")],
    url: None,
    url_group: None,
    content_based_deduplication: False,
    method: http.Post,
  )
}

fn prepare_headers(req: PublishRequest(body, Ready)) -> List(#(String, String)) {
  dict.new()
  |> dict.insert("content-type", "text/plain")
  |> dict.insert("upstash-method", req.method |> http.method_to_string)
  |> dict.insert(
    "upstash-content-based-deduplication",
    req.content_based_deduplication |> bool.to_string |> string.lowercase
  )
  |> dict.merge(dict.from_list(req.headers))
  |> dict.to_list()
}
