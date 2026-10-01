# synthient-ruby

![Synthient](https://raw.githubusercontent.com/synthient/synthient-ruby/main/assets/readme-header.svg)

[![Gem Version](https://img.shields.io/gem/v/synthient)](https://rubygems.org/gems/synthient)
[![test](https://github.com/synthient/synthient-ruby/actions/workflows/test.yml/badge.svg)](https://github.com/synthient/synthient-ruby/actions/workflows/test.yml)
[![lint](https://github.com/synthient/synthient-ruby/actions/workflows/lint.yml/badge.svg)](https://github.com/synthient/synthient-ruby/actions/workflows/lint.yml)

The official Ruby client for the [Synthient API](https://docs.synthient.com): IP and domain intelligence, account details, and real-time and bulk data feeds.

## Install

```sh
bundle add synthient
```

Requires Ruby 3.3 or later.

## Usage

```ruby
require "synthient"

client = Synthient::Client.new # reads SYNTHIENT_API_KEY

info = client.lookup_ip("8.8.8.8")
puts info.intelligence&.risk_score
```

Look up many addresses in one request:

```ruby
client.lookup_ips(["8.8.8.8", "1.1.1.1"]).each do |result|
  puts "#{result.ip} #{result.intelligence&.risk_score}"
end
```

Consume a real-time feed:

```ruby
client.proxies.stream do |event|
  puts "#{event.ip} #{event.provider}"
end
```

## Documentation

Every class and method is documented on [RubyDoc.info](https://rubydoc.info/gems/synthient), including errors, retries, exports, and downloads, and the gem ships RBS signatures. Runnable programs are in [examples](https://github.com/synthient/synthient-ruby/tree/main/examples), for example `bundle exec ruby examples/lookup_ip.rb 8.8.8.8`. Guides and field references are at [docs.synthient.com](https://docs.synthient.com). `require "synthient/grpcschema"` loads `Synthient::GRPCSchema`, which fetches the protobuf schema of the Synthient gRPC API; it needs `gem install grpc google-protobuf`.

## License

[Apache 2.0](https://github.com/synthient/synthient-ruby/blob/main/LICENSE)
