<p align="center">
  <a href="https://synthient.com">
    <img src="https://raw.githubusercontent.com/synthient/synthient-ruby/main/assets/logo.svg" height="96" alt="Synthient logo">
  </a>
</p>
<h3 align="center">Synthient</h3>
<p align="center">High-fidelity data on residential proxies, VPNs, and other anonymized IPs.</p>
<p align="center">
  <a href="https://docs.synthient.com">Documentation</a> ·
  <a href="https://rubydoc.info/gems/synthient">API reference</a> ·
  <a href="https://docs.synthient.com/misc/support">Support</a>
</p>

# synthient-ruby

The `synthient` gem is the official Ruby SDK for the [Synthient API](https://docs.synthient.com): IP and domain intelligence, account details, and real-time and bulk data feeds.

[![Gem Version](https://img.shields.io/gem/v/synthient)](https://rubygems.org/gems/synthient)
[![test](https://github.com/synthient/synthient-ruby/actions/workflows/test.yml/badge.svg)](https://github.com/synthient/synthient-ruby/actions/workflows/test.yml)
[![lint](https://github.com/synthient/synthient-ruby/actions/workflows/lint.yml/badge.svg)](https://github.com/synthient/synthient-ruby/actions/workflows/lint.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://github.com/synthient/synthient-ruby/blob/main/LICENSE)

## Table of Contents

- [synthient-ruby](#synthient-ruby)
  - [SDK Installation](#sdk-installation)
  - [Requirements](#requirements)
  - [API Keys](#api-keys)
  - [Authentication](#authentication)
  - [SDK Example Usage](#sdk-example-usage)
  - [Available Resources and Operations](#available-resources-and-operations)
  - [Streaming](#streaming)
  - [Pagination](#pagination)
  - [Downloads](#downloads)
  - [Retries](#retries)
  - [Timeouts](#timeouts)
  - [Error Handling](#error-handling)
  - [Server Selection](#server-selection)
  - [Custom HTTP Client](#custom-http-client)
  - [Debugging](#debugging)
  - [gRPC Schema](#grpc-schema)
- [Development](#development)
  - [Maturity](#maturity)
  - [Contributions](#contributions)
  - [License](#license)

## SDK Installation

### Bundler

```sh
bundle add synthient
```

### RubyGems

```sh
gem install synthient
```

### gRPC schema fetcher

The [gRPC schema fetcher](#grpc-schema) is part of the gem but needs the `grpc` and `google-protobuf` gems:

```sh
bundle add grpc google-protobuf
```

## Requirements

Ruby 3.3 or later. The gem uses only Ruby's standard library. It ships RBS signatures, so [Steep](https://github.com/soutaro/steep) can check your calls with `library "synthient"` in your Steepfile.

## API Keys

Every request needs a Synthient API key. Keys are issued from the Synthient dashboard; if you don't have one, [contact us](mailto:contact@synthient.com). A key's scopes decide what it can call: `BASIC` covers the lookups and `account`, and each feed has its own scopes, listed under [Feeds](#feeds).

If a request fails even though you are sending a key:

- **401 Unauthorized**: the key is malformed, unknown, or revoked.
- **402 Payment Required**: the team is out of lookup credits.
- **403 Forbidden**: the key lacks the scope for that endpoint or feed.

`account` shows the key's scopes and the team's remaining credits.

## Authentication

This SDK supports the following security scheme:

| Name      | Type    | Scheme             | Environment Variable |
| --------- | ------- | ------------------ | -------------------- |
| `api_key` | API key | `x-api-key` header | `SYNTHIENT_API_KEY`  |

`Synthient::Client.new` reads the key from `SYNTHIENT_API_KEY`. To read it from somewhere else, such as a secret manager, pass `api_key:`:

```ruby
client = Synthient::Client.new(api_key: ENV.fetch("SYNTHIENT_PRODUCTION_KEY"))
```

Creating a client makes no network calls. To check a key, call `account`, which costs no credits.

## SDK Example Usage

### Look up an IP address

Get the network, location, and risk intelligence for an IPv4 or IPv6 address, given as a `String` or an `IPAddr`. Each lookup costs one credit; failed lookups are free.

```ruby
require "synthient"

client = Synthient::Client.new # reads SYNTHIENT_API_KEY

info = client.lookup_ip("8.8.8.8")
intelligence = info.intelligence
puts "#{intelligence.risk_score} #{intelligence.categories.join(", ")}" if intelligence

client.close
```

`network`, `location`, and `intelligence` are nil when the API has no data for them. Responses are frozen `Data` objects that support `to_h` and pattern matching.

A client keeps its connections open and is safe to share between threads, so create one, reuse it, and call `close` when you are done. The examples below reuse `client`, and runnable programs are in [examples](https://github.com/synthient/synthient-ruby/tree/main/examples).

### Look up many IP addresses

Look up as many as 1000 addresses in one request for `ceil(n * 0.9)` credits. Private and reserved addresses are skipped and duplicates are merged, so match results by `ip`.

```ruby
results = client.lookup_ips(["8.8.8.8", "1.1.1.1"])
results.each do |result|
  puts "#{result.ip} #{result.intelligence&.risk_score}"
end
```

### Look up a domain

Get the honeypot traffic observed for a domain and its most recent events. Each lookup costs one credit.

```ruby
domain = client.lookup_domain("example.com", limit: 10)
puts "#{domain.status} #{domain.stats.events_24h}"
domain.recent_events.each do |event|
  puts "#{event.timestamp.iso8601} #{event.target_subdomain} #{event.port}"
end
```

### Check your account

Get the key's account, scopes, and remaining lookup credits, at no cost.

```ruby
account = client.account
puts "#{account.organization.name} #{account.scopes.join(", ")} #{account.lookup_quota.credits}"
```

## Available Resources and Operations

<details open>
<summary>Available methods</summary>

### [Client](https://rubydoc.info/gems/synthient/Synthient/Client)

- [`lookup_ip`](https://rubydoc.info/gems/synthient/Synthient/Client#lookup_ip-instance_method) - Look up an IPv4 or IPv6 address
- [`lookup_ips`](https://rubydoc.info/gems/synthient/Synthient/Client#lookup_ips-instance_method) - Look up as many as 1000 addresses in one request
- [`lookup_domain`](https://rubydoc.info/gems/synthient/Synthient/Client#lookup_domain-instance_method) - Look up the honeypot traffic observed for a domain
- [`account`](https://rubydoc.info/gems/synthient/Synthient/Client#account-instance_method) - Get the key's account, scopes, and remaining lookup credits
- [`health`](https://rubydoc.info/gems/synthient/Synthient/Client#health-instance_method) - Check that the API and its dependencies are healthy

### [Feeds](https://rubydoc.info/gems/synthient/Synthient/Feed)

Each feed is a method of the client, such as `client.proxies`, and has the same methods:

- [`stream`](https://rubydoc.info/gems/synthient/Synthient/Feed#stream-instance_method) - Yield the feed's real-time events
- [`list_exports`](https://rubydoc.info/gems/synthient/Synthient/Feed#list_exports-instance_method) - List one page of the feed's Parquet exports, newest first
- [`each_export`](https://rubydoc.info/gems/synthient/Synthient/Feed#each_export-instance_method) - Yield every export, fetching pages as needed
- [`export_meta`](https://rubydoc.info/gems/synthient/Synthient/Feed#export_meta-instance_method) - Get an export's checksum, size, row count, and Parquet schema
- [`download`](https://rubydoc.info/gems/synthient/Synthient/Feed#download-instance_method) - Download an export's Parquet file in chunks
- [`download_url`](https://rubydoc.info/gems/synthient/Synthient/Feed#download_url-instance_method) - Get a presigned URL for an export's Parquet file, valid for 24 hours

| Method         | Data                                          | Event type         | Stream scope            | Export scope          |
| -------------- | --------------------------------------------- | ------------------ | ----------------------- | --------------------- |
| `proxies`      | Residential, mobile, and datacenter proxies   | `ProxyEvent`       | `PROXY_FIREHOSE`        | `PROXY_FEEDS`         |
| `anonymizers`  | VPN and anonymizer IP ranges                  | `AnonymizerEvent`  | `ANONYMIZERS_STREAM`    | `ANONYMIZERS_FEED`    |
| `torrents`     | BitTorrent DHT and tracker peers              | `TorrentEvent`     | `TORRENTS_STREAM`       | `TORRENTS_FEED`       |
| `ja4t`         | JA4T TCP fingerprints                         | `JA4TEvent`        | `JA4T_STREAM`           | `JA4T_FEED`           |
| `helios_http`  | Helios honeypot HTTP requests                 | `HeliosHTTPEvent`  | `HONEYPOT_HTTP_STREAM`  | `HONEYPOT_HTTP_FEED`  |
| `helios_https` | Helios honeypot TLS ClientHellos              | `HeliosHTTPSEvent` | `HONEYPOT_HTTPS_STREAM` | `HONEYPOT_HTTPS_FEED` |
| `helios_dns`   | Helios honeypot tunnel destinations           | `HeliosDNSEvent`   | `HONEYPOT_DNS_STREAM`   | `HONEYPOT_DNS_FEED`   |
| `helios_adb`   | Helios honeypot Android Debug Bridge commands | `HeliosADBEvent`   | `HONEYPOT_ADB_STREAM`   | `HONEYPOT_ADB_FEED`   |

</details>

## Streaming

`stream` yields a feed's real-time events. Each call opens a connection, and breaking out of the block closes it:

```ruby
loop do
  client.proxies.stream do |event|
    puts "#{event.ip} #{event.provider} #{event.type}"
  end
rescue Synthient::APIError => e
  raise if [401, 403].include?(e.status)

  warn "proxy stream: #{e.message}"
  # Avoid reconnecting in a tight loop.
  sleep 2
rescue Synthient::Error => e
  warn "proxy stream: #{e.message}"
  sleep 2
end
```

- The server closes each stream after up to 30 minutes. `stream` then returns normally, and the loop reconnects at once.
- A 401 or 403 stops the loop, because reconnecting can't fix a rejected key or a missing scope.
- Any other failure raises a `Synthient::Error`, and the loop waits 2 seconds before reconnecting.
- Events sent while disconnected are missed. The API has no resume cursor.

Without a block, `stream` returns an `Enumerator` that connects when you iterate it.

## Pagination

`list_exports` returns one page of a feed's exports, newest first. Pass `page.next_cursor` as `cursor:` to get the next page; it is nil on the last one.

```ruby
page = client.proxies.list_exports(limit: 50)
page.exports.each do |export|
  puts "#{export.id} #{export.kind} #{export.row_count}"
end
```

`each_export` fetches the pages for you as the block needs them:

```ruby
client.proxies.each_export do |export|
  puts "#{export.id} #{export.kind} #{export.row_count}"
end
```

Without a block, it returns an `Enumerator`, so `client.proxies.each_export.first(10)` fetches only the pages it needs.

On the first page, the newest hourly export has the ID `"latest"`, a moving alias for the freshest export. Its `date` and `hour` give its stable ID, such as `"2026-10-14/21"`.

## Downloads

Exports are Parquet files. `download` yields a file's bytes in chunks as they arrive:

```ruby
File.open("proxies.parquet", "wb") do |file|
  client.proxies.download("latest") { |chunk| file.write(chunk) }
end
```

- Name an export by its `id` from a listing, by `"latest"`, or by a `Date` or `Time` for a UTC day or hour.
- `export_meta` returns the file's SHA-256 `checksum`. Use a fixed ID for both calls, because `"latest"` can move between them.
- `download_url` returns a presigned URL that works without a key for 24 hours, so treat it as a secret. Your API key is never sent to the storage host.
- Hourly exports roll into the daily export shortly after 00:30 UTC the next day. After that, a request for the hour raises a 400.

## Retries

The client retries a failed request up to twice, backing off exponentially with jitter and honoring `Retry-After`:

| Requests                    | Retried on                                                                                   |
| --------------------------- | -------------------------------------------------------------------------------------------- |
| Account and feed requests   | 500, 502, 503, and 504, most network failures, and 429 with `Retry-After`                    |
| Billed lookups and `health` | Only 429 with `Retry-After`, which comes before any work, so a lookup is never charged twice |

A 429 without `Retry-After` means the monthly request budget is spent or too many streams are open, so it is raised at once. Downloads from the storage host are never retried.

Set the number of retries with `max_retries:`. Zero disables them:

```ruby
client = Synthient::Client.new(max_retries: 4)
```

## Timeouts

The client sets no overall timeout, because streams and downloads are long-lived. Instead, `timeout:` limits each read or write, 60 seconds by default, and `open_timeout:` limits connecting, 10 seconds by default:

```ruby
client = Synthient::Client.new(timeout: 30, open_timeout: 5)
```

The server sends a blank keepalive line on a quiet stream about every 15 seconds, so keep `timeout:` above that. Running out of time raises `Synthient::TimeoutError`.

## Error Handling

A request that fails with an error status raises a [`Synthient::APIError`](https://rubydoc.info/gems/synthient/Synthient/APIError):

| Attribute     | Type                          | Description                                  |
| ------------- | ----------------------------- | -------------------------------------------- |
| `status`      | `Integer`                     | HTTP status code, such as `404`              |
| `type`        | `String?`                     | URI identifying the problem type             |
| `title`       | `String?`                     | Short summary of the problem type            |
| `detail`      | `String?`                     | Explanation of this occurrence               |
| `errors`      | `Hash[String, Array[String]]` | Validation messages by request field         |
| `request_id`  | `String?`                     | Request ID to give Synthient support         |
| `retry_after` | `Numeric?`                    | Seconds the server asked you to wait, or nil |

Its `message` holds only the HTTP status, so it is safe to log. The attributes hold untrusted server data.

### Example

```ruby
begin
  client.lookup_ip("8.8.8.8")
rescue Synthient::APIError => e
  case e.status
  when 402
    puts "out of lookup credits"
  when 429
    puts e.retry_after ? "rate limited, retry after #{e.retry_after}s" : "monthly request budget spent"
  else
    puts "request #{e.request_id} failed: #{e.detail || e.title}"
  end
end
```

### Error Types

- [`Synthient::Error`](https://rubydoc.info/gems/synthient/Synthient/Error): the base class of every error the SDK raises for a failed request.
- [`Synthient::APIError`](https://rubydoc.info/gems/synthient/Synthient/APIError): the API, or the storage host during `download`, returned an error status.
- [`Synthient::ConnectionError`](https://rubydoc.info/gems/synthient/Synthient/ConnectionError): the request couldn't be sent or the response couldn't be read.
- [`Synthient::TimeoutError`](https://rubydoc.info/gems/synthient/Synthient/TimeoutError): a `ConnectionError` for a connect, read, or write that ran out of time.
- [`Synthient::DecodeError`](https://rubydoc.info/gems/synthient/Synthient/DecodeError): a successful response didn't match the API schema.
- `ArgumentError` and `TypeError`: invalid arguments, such as a missing API key, raised before any request is sent.
- `IOError`: the client was used after `close`.

<details><summary>Status codes</summary>

<br />

| Status | Meaning                                                                                          |
| ------ | ------------------------------------------------------------------------------------------------ |
| 400    | The request is invalid, such as an hourly export that was rolled up                              |
| 401    | The API key is malformed, unknown, or revoked                                                    |
| 402    | The team is out of lookup credits                                                                |
| 403    | The key lacks the scope for the endpoint or feed                                                 |
| 404    | The export doesn't exist, or a daily export is still rolling up (`retry_after` is set)           |
| 422    | The input is invalid, such as a private address or a malformed domain                            |
| 429    | Rate limited if `retry_after` is set; otherwise the budget is spent or too many streams are open |
| 5xx    | The server failed                                                                                |

</details>

## Server Selection

### Override Server URL Per-Client

The default server is `https://api.synthient.com/api/v4`. Use `base_url:` to send requests elsewhere, such as a mock server in tests:

```ruby
client = Synthient::Client.new(base_url: "http://localhost:8080/api/v4")
```

## Custom HTTP Client

The client uses Ruby's `Net::HTTP` and doesn't accept a replacement. To use a proxy, set `http_proxy`:

```sh
export http_proxy=http://proxy.example.com:8080
```

- `Net::HTTP` uses `http_proxy` for HTTPS requests too and ignores `https_proxy`. `no_proxy` exempts hosts.
- Export downloads from storage go through the same proxy.
- `Net::HTTP`'s own retry is off, so a stale keep-alive connection never resends a billed lookup.

`user_agent: "my-app/1.2"` adds your product token to the `User-Agent` header.

## Debugging

`response_hook:` takes any callable and calls it after every API response, including retries, pages, and stream handshakes, with a `Synthient::ResponseMetadata` holding the status, request ID, rate limit, and headers:

```ruby
client = Synthient::Client.new(
  response_hook: lambda do |meta|
    warn "status=#{meta.status} request_id=#{meta.request_id}"
    limit = meta.rate_limit
    warn "rate limit: #{limit.remaining} of #{limit.limit} left" if limit
  end
)
```

The hook runs on the thread that made the request, and exceptions it raises propagate to that call.

> [!WARNING]
> Response headers can contain secrets, such as presigned download URLs. Avoid logging `meta.headers` in production.

## gRPC Schema

[`Synthient::GRPCSchema`](https://rubydoc.info/gems/synthient/Synthient/GRPCSchema) fetches the protobuf schema of the [Synthient gRPC API](https://docs.synthient.com/grpc) through server reflection:

```ruby
require "synthient/grpcschema"

begin
  schema = Synthient::GRPCSchema.fetch # reads SYNTHIENT_API_KEY
rescue Synthient::GRPCSchema::SchemaError => e
  explanation = Synthient::GRPCSchema.explain(e)
  abort explanation ? "#{explanation} #{e.message}" : e.message
end
schema.descriptor_set.file.each do |file|
  puts "#{file.name} #{file.package}"
end
```

`schema.descriptor_set` is a `Google::Protobuf::FileDescriptorSet`. `explain` describes common gRPC errors in plain language.

# Development

## Maturity

This SDK follows [Semantic Versioning](https://semver.org). Breaking changes ship only in a new major version, so a constraint such as `gem "synthient", "~> 1.0"` never picks them up.

## Contributions

Bug reports and feature requests are welcome as [GitHub issues](https://github.com/synthient/synthient-ruby/issues). For questions about the API or your account, contact [Synthient support](https://docs.synthient.com/misc/support).

## License

[Apache 2.0](https://github.com/synthient/synthient-ruby/blob/main/LICENSE)
