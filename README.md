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

The [gRPC schema fetcher](#grpc-schema) is part of the gem, but it needs the `grpc` and `google-protobuf` gems, which `synthient` does not depend on. Add them to use it:

```sh
bundle add grpc google-protobuf
```

## Requirements

Ruby 3.3 or later. The gem has no runtime dependencies outside Ruby's standard library. It ships RBS signatures, so [Steep](https://github.com/soutaro/steep) can check your calls once your Steepfile declares `library "synthient"`.

## API Keys

Every request to the HTTP API needs a Synthient API key. Keys are issued from the Synthient dashboard; if you don't have one yet, [contact us](mailto:contact@synthient.com). Each key carries scopes that decide what it can call. `BASIC` covers the lookups and `account`, and each feed has one scope for its real-time stream and one for its exports, listed under [Feeds](#feeds). See [Authentication](https://docs.synthient.com/authentication) for how scopes work.

If a request fails even though you are sending a key, it is usually one of these:

- **401 Unauthorized**: the key is malformed, unknown, or revoked. Check that it was loaded from the environment and isn't truncated.
- **402 Payment Required**: the team is out of lookup credits. `account` reports the remaining balance and when it resets.
- **403 Forbidden**: the key lacks the scope for that endpoint or feed. `account` lists the key's scopes.

## Authentication

This SDK supports the following security scheme:

| Name      | Type    | Scheme             | Environment Variable |
| --------- | ------- | ------------------ | -------------------- |
| `api_key` | API key | `x-api-key` header | `SYNTHIENT_API_KEY`  |

`Synthient::Client.new` reads the key from `SYNTHIENT_API_KEY`. To supply it another way, such as from a secret manager, pass `api_key:`. Don't write the key into your code:

```ruby
client = Synthient::Client.new(api_key: ENV.fetch("SYNTHIENT_PRODUCTION_KEY"))
```

A missing or blank key raises `ArgumentError`. Creating a client makes no network calls, so an invalid key shows up as a 401 on the first request. The key is sent only to the Synthient API, never to the storage host that serves export downloads.

## SDK Example Usage

### Look up an IP address

Get the network, location, and risk intelligence for an IPv4 or IPv6 address, given as a `String` or an `IPAddr`. Each lookup costs one credit, and failed lookups are free.

```ruby
require "synthient"

client = Synthient::Client.new # reads SYNTHIENT_API_KEY

info = client.lookup_ip("8.8.8.8")
intelligence = info.intelligence
puts "#{intelligence.risk_score} #{intelligence.categories.join(", ")}" if intelligence

client.close
```

`network`, `location`, and `intelligence` are nil when the API has no data for that section, so check them before reading their fields. Responses are frozen `Data` objects, so they support `to_h` and pattern matching.

A client keeps a pool of keep-alive connections and is safe to share between threads, so create one, reuse it, and call `close` when you are done. In a forking server, a child process never reuses connections inherited from its parent. The examples below reuse `client`. Runnable programs are in [examples](https://github.com/synthient/synthient-ruby/tree/main/examples), for example `bundle exec ruby examples/lookup_ip.rb 8.8.8.8`.

### Look up many IP addresses

Look up as many as 1000 addresses in one request, billed at `ceil(n * 0.9)` credits for the `n` distinct addresses looked up. Private and reserved addresses are skipped and duplicates collapse into one result, so match results by `ip` rather than by position. An address that isn't valid raises `ArgumentError` before anything is sent.

```ruby
results = client.lookup_ips(["8.8.8.8", "1.1.1.1"])
results.each do |result|
  puts "#{result.ip} #{result.intelligence&.risk_score}"
end
```

### Look up a domain

Get the honeypot traffic observed for a domain, with its most recent events. A domain that has never been observed returns an inactive status and zero counts rather than an error. Each lookup costs one credit.

```ruby
domain = client.lookup_domain("example.com", limit: 10)
puts "#{domain.status} #{domain.stats.events_24h}"
domain.recent_events.each do |event|
  puts "#{event.timestamp.iso8601} #{event.target_subdomain} #{event.port}"
end
```

### Check your account

Get the account that owns the API key, with the key's scopes and the team's remaining lookup credits. It costs no credits.

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
- [`account`](https://rubydoc.info/gems/synthient/Synthient/Client#account-instance_method) - Get the account that owns the API key, the key's scopes, and the team's remaining lookup credits
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

`stream` yields a feed's real-time events as they arrive. Each call opens a new connection, and breaking out of the block closes it. The server keeps a stream open for up to 30 minutes and then closes it, at which point `stream` returns normally. The API has no resume cursor, so call it again to reconnect:

```ruby
loop do
  client.proxies.stream do |event|
    puts "#{event.ip} #{event.provider} #{event.type}"
  end
rescue Synthient::APIError => e
  raise if [401, 403].include?(e.status)

  warn "proxy stream: #{e.message}"
  # Pause after a failure so a failing stream doesn't reconnect in a tight loop.
  sleep 2
rescue Synthient::Error => e
  warn "proxy stream: #{e.message}"
  sleep 2
end
```

The loop stops on a 401 or 403, because reconnecting can't fix a rejected key or a missing scope. Any other failure, such as another error response or a dropped connection, raises a `Synthient::Error`, and the loop waits 2 seconds before reconnecting. After the server's routine close, it reconnects at once. A 429 `APIError` without `retry_after` means the key already has too many open streams. Without a block, `stream` returns an `Enumerator` that opens the connection when you iterate it.

## Pagination

`list_exports` returns one page of a feed's exports, newest first:

```ruby
page = client.proxies.list_exports(limit: 50)
page.exports.each do |export|
  puts "#{export.id} #{export.kind} #{export.row_count}"
end
```

To get the next page, pass `page.next_cursor` as `cursor:`. It is nil on the last page. `each_export` does the paging for you. It fetches pages as the block needs them and stops fetching when you break out:

```ruby
client.proxies.each_export do |export|
  puts "#{export.id} #{export.kind} #{export.row_count}"
end
```

Without a block, `each_export` returns an `Enumerator`, so `client.proxies.each_export.first(10)` fetches only the pages it needs.

On the first page, the newest hourly export has the ID `"latest"`, a moving alias for the freshest export. To keep a stable ID, build it from the export's `date` and `hour`, such as `"2026-10-14/21"`.

## Downloads

Exports are Parquet files. Identify one by the `id` of an `Export` from a listing, by `"latest"` for the freshest one, or by a `Date` (not a `DateTime`) or `Time` for a UTC day or hour. Strings such as `"2026-10-15"` and `"2026-10-15/13"` work too. `download` yields the file's bytes in chunks as they arrive:

```ruby
File.open("proxies.parquet", "wb") do |file|
  client.proxies.download("latest") { |chunk| file.write(chunk) }
end
```

The file comes from a presigned storage URL that is requested without your API key, and that request is not retried. The SDK doesn't verify the bytes, so compare their SHA-256 with the export's `checksum`, from a listing or `export_meta`. Use the same stable ID for the checksum and the download, because `"latest"` can move to a newer export between the two calls. `download_url` returns the presigned URL itself for tools that read Parquet over HTTPS. The URL grants access without a key for 24 hours, so treat it as a secret.

An hourly export is available until its day's daily export is rolled up, shortly after 00:30 UTC the next day. After that, requests for the hour raise a 400 `APIError`. While a daily export is being rolled up, requests for it raise a 404 `APIError` with `retry_after` set.

## Retries

The client retries a failed request up to twice by default, backing off exponentially with jitter and honoring `Retry-After`:

- Account and feed requests to the API are retried on 500, 502, 503, and 504 responses, on network failures and timeouts before a response arrives (except TLS errors), and on 429 responses that carry `Retry-After`. The storage request behind `download` is not retried, and neither is a failure while reading a stream or download.
- Billed lookups (`lookup_ip`, `lookup_ips`, and `lookup_domain`) are retried only on 429 responses that carry `Retry-After`, which the rate limiter returns before doing any work, so a lookup is never charged twice. `health` is retried the same way, so an unhealthy API is reported at once.

A 429 without `Retry-After` means the key's monthly request budget is spent or it has too many open streams, so it is raised without a retry. A `Retry-After` longer than 60 seconds is raised to you instead of waited out.

To change the number of retries, pass `max_retries:` when creating the client. Zero disables retries:

```ruby
client = Synthient::Client.new(max_retries: 4)
```

## Timeouts

Each read or write waits at most `timeout:` seconds, 60 by default, and opening a connection waits at most `open_timeout:` seconds, 10 by default. They limit each step rather than a whole call, so streams and downloads run as long as data keeps arriving. A quiet stream receives only a blank keepalive line about every 15 seconds, so keep `timeout:` above that. Running out of time raises `Synthient::TimeoutError`:

```ruby
client = Synthient::Client.new(timeout: 30, open_timeout: 5)
```

## Error Handling

A request that fails with an error status raises a [`Synthient::APIError`](https://rubydoc.info/gems/synthient/Synthient/APIError). It has the following attributes:

| Attribute     | Type                          | Description                                                                                     |
| ------------- | ----------------------------- | ----------------------------------------------------------------------------------------------- |
| `status`      | `Integer`                     | HTTP response status code, such as `404`                                                        |
| `type`        | `String?`                     | URI identifying the problem type, such as `https://docs.synthient.com/errors/validation-failed` |
| `title`       | `String?`                     | Short summary of the problem type                                                               |
| `detail`      | `String?`                     | Explanation of this occurrence. For a plain-text error, the response body                       |
| `errors`      | `Hash[String, Array[String]]` | Validation messages by request field                                                            |
| `request_id`  | `String?`                     | Request ID to give Synthient support                                                            |
| `retry_after` | `Numeric?`                    | Seconds the server asked you to wait before retrying, or nil                                    |

Its `message` holds only the status, such as `429 Too Many Requests`. The other attributes hold untrusted server data that can be sensitive, so log them deliberately.

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

- [`Synthient::Error`](https://rubydoc.info/gems/synthient/Synthient/Error): the base class of every error the SDK raises for a failed request. It is raised itself when a storage redirect is invalid or loops, or when export pagination repeats a cursor.
- [`Synthient::APIError`](https://rubydoc.info/gems/synthient/Synthient/APIError): the API, or the storage host serving a download, returned an error status.
- [`Synthient::ConnectionError`](https://rubydoc.info/gems/synthient/Synthient/ConnectionError): the request couldn't be sent or the response couldn't be read. The underlying exception is its `cause`.
- [`Synthient::TimeoutError`](https://rubydoc.info/gems/synthient/Synthient/TimeoutError): a connect, read, or write ran out of time. It is a `ConnectionError`.
- [`Synthient::DecodeError`](https://rubydoc.info/gems/synthient/Synthient/DecodeError): a successful response didn't match the API schema.
- `ArgumentError` and `TypeError`: an argument was invalid, such as a missing API key or a malformed IP address. Nothing was sent.
- `IOError`: the client was used after `close`.

<details><summary>Status codes</summary>

<br />

| Status | Meaning                                                                                                            |
| ------ | ------------------------------------------------------------------------------------------------------------------ |
| 400    | The request is invalid, such as asking for an hourly export that has been rolled up                                |
| 401    | The API key is malformed, unknown, or revoked                                                                      |
| 402    | The team is out of lookup credits                                                                                  |
| 403    | The key lacks the scope for the endpoint or feed                                                                   |
| 404    | The export does not exist, or a daily export is still being rolled up and `retry_after` is set                     |
| 422    | The input is invalid, such as a private or reserved address, a malformed domain, or a batch with no usable address |
| 429    | With `retry_after`, the rate limit was hit. Without it, the request budget is spent or too many streams are open   |
| 5xx    | The server failed. Account and feed requests are retried on 500, 502, 503, and 504                                 |

</details>

## Server Selection

### Override Server URL Per-Client

The default server is `https://api.synthient.com/api/v4`. To send requests elsewhere, such as through a gateway or to a mock server in tests, pass `base_url:` when creating the client. The URL includes the version path:

```ruby
client = Synthient::Client.new(base_url: "http://localhost:8080/api/v4")
```

## Custom HTTP Client

The client sends requests with Ruby's `Net::HTTP` and doesn't accept a replacement. It turns off `Net::HTTP`'s own retry, so a stale keep-alive connection never resends a billed lookup.

`Net::HTTP` takes proxy settings from the environment. To route requests through a proxy, set `http_proxy`, which `Net::HTTP` uses for HTTPS requests too. It ignores `https_proxy`, and `no_proxy` exempts hosts from the proxy:

```sh
export http_proxy=http://proxy.example.com:8080
```

Export downloads from storage go through the same proxy. To identify your application, `user_agent: "my-app/1.2"` appends a product token to the `User-Agent` header.

## Debugging

`response_hook:` takes anything that responds to `call`, and calls it after every API response arrives, including each retry, page, and stream handshake. It receives a `Synthient::ResponseMetadata` with the status code, the request ID to give Synthient support, the operation's rate limit, and a frozen copy of the response headers with lowercase names:

```ruby
client = Synthient::Client.new(
  response_hook: lambda do |meta|
    warn "status=#{meta.status} request_id=#{meta.request_id}"
    limit = meta.rate_limit
    warn "rate limit: #{limit.remaining} of #{limit.limit} left" if limit
  end
)
```

The hook runs synchronously on the thread that made the request, before the response body is read, and exceptions it raises propagate to that call. Storage download responses are not passed to it.

> [!WARNING]
> Response headers can contain secrets, such as presigned download URLs. Avoid logging `meta.headers` in production.

## gRPC Schema

[`Synthient::GRPCSchema`](https://rubydoc.info/gems/synthient/Synthient/GRPCSchema) fetches the protobuf schema of the [Synthient gRPC API](https://docs.synthient.com/grpc) through gRPC server reflection. It needs the `grpc` and `google-protobuf` gems, as described under [SDK Installation](#sdk-installation):

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

`schema.descriptor_set` is a `Google::Protobuf::FileDescriptorSet` with each file after the files it imports. `explain` describes common gRPC errors in plain language, and returns nil for the rest. A fetch gives up after `timeout:` seconds, 30 by default.

# Development

## Maturity

This SDK follows [Semantic Versioning](https://semver.org). Breaking changes to its public API ship only in a new major version, so a constraint such as `gem "synthient", "~> 1.0"` picks up new features and fixes without breaking changes.

## Contributions

Bug reports and feature requests are welcome as [GitHub issues](https://github.com/synthient/synthient-ruby/issues). For questions about the API or your account, contact [Synthient support](https://docs.synthient.com/misc/support).

## License

[Apache 2.0](https://github.com/synthient/synthient-ruby/blob/main/LICENSE)
