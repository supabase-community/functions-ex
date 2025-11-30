# Supabase Functions

[Edge Functions](https://supabase.com/docs/guides/functions) client implementation for the [Supabase Potion](https://github.com/supabase-community/supabase-ex) SDK in Elixir

## Installation

```elixir
def deps do
  [
    {:supabase_potion, "~> 0.6"},
    {:supabase_functions, "~> 0.1"}
  ]
end
```

## Usage

Given a simple Edge Function that simply echos a raw string:

```ts
// simple-text/index.ts
Deno.serve(async (req) => {
  return new Response("Hello from Deno!", {
    headers: { "Content-Type": "text/plain" }
  });
});
```

From your Elixir server, after having started your `Supabase.Client` yo ucan inke this function as

```elixir
client = Supabase.init_client!("SUPABASE_URl", "SUPABASE_KEY")

Supabase.Functions.invoke(client, "simple-text")
# {:ok, %Supabase.Response{status: 200, body: "Hello from Deno!"}}
```

It also work with data streaming, given an Edge Function

```ts
// stream-data/index.ts
Deno.serve(async (req) => {
  const stream = new ReadableStream({
    start(controller) {
      let count = 0;
      const interval = setInterval(() => {
        if (count >= 5) {
          clearInterval(interval);
          controller.close();
          return;
        }
        const message = `Event ${count}\n`;
        controller.enqueue(new TextEncoder().encode(message));
        count++;
      }, 1000);
    }
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      "Connection": "keep-alive"
    }
  });
});
```

The you could invoke it as

```elixir
client = Supabase.init_client!("SUPABASE_URl", "SUPABASE_KEY")

# you can control the response streaming handling too (optional)
on_response = fn {status, headers, body} ->
  require Logger

  Logger.info("received response with #{status} status")
  Logger.info("received #{inspect(headers, pretty: true)} headers")

  file = File.stream!("output.txt", [:write, :utf8])

  body
  |> Stream.into(file)
  |> Stream.run()
end

Supabase.Functions.invoke(client, "stream-data", on_response: on_response)
# :ok
```

## Timeout Support

You can control the timeout for function invocations using the `timeout` option. If no timeout is specified, requests will timeout after 15 seconds by default.

```elixir
client = Supabase.init_client!("SUPABASE_URL", "SUPABASE_KEY")

# Basic invocation with default timeout (15 seconds)
{:ok, response} = Supabase.Functions.invoke(client, "my-function")

# Custom timeout (5 seconds)
{:ok, response} = Supabase.Functions.invoke(client, "my-function", timeout: 5_000)

# Timeout with body and headers  
{:ok, response} = Supabase.Functions.invoke(client, "my-function", 
  body: %{data: "value"}, 
  headers: %{"x-custom" => "header"},
  timeout: 30_000)

# Streaming with timeout
on_response = fn {status, headers, body} ->
  # Handle streaming response
  {:ok, body}
end

{:ok, response} = Supabase.Functions.invoke(client, "my-function",
  on_response: on_response,
  timeout: 10_000)
```

This feature provides:
- **Request cancellation**: Long-running requests will timeout and be cancelled
- **Better resource management**: Prevents hanging connections
- **Comprehensive timeout coverage**: Sets both receive timeout (per-chunk) and request timeout (complete response)
- **Feature parity with JS client**: Matches timeout functionality in the JavaScript SDK

## Dynamic Auth Token Updates

You can update authorization tokens dynamically using two approaches, providing feature parity with the JavaScript client's `setAuth(token)` method:

### Option 1: Functional Update

Create a new client with an updated auth token:

```elixir
client = Supabase.init_client!("SUPABASE_URL", "SUPABASE_KEY")

# Update auth token functionally
updated_client = Supabase.Functions.update_auth(client, "new_jwt_token")
{:ok, response} = Supabase.Functions.invoke(updated_client, "my-function")
```

### Option 2: Per-Request Override

Override the authorization token for a specific request:

```elixir
client = Supabase.init_client!("SUPABASE_URL", "SUPABASE_KEY")

# Use a different token for this request only
{:ok, response} = Supabase.Functions.invoke(client, "my-function", auth: "user_jwt_token")

# Original client remains unchanged for subsequent calls
{:ok, response2} = Supabase.Functions.invoke(client, "another-function")
```

### Benefits

- **Token rotation support**: Easily update tokens without recreating clients
- **Better performance**: Avoid the overhead of creating new client instances
- **Flexibility**: Use different tokens per request or update client globally
- **Feature parity**: Matches the JavaScript client's `setAuth()` functionality
- **Immutability**: Original client instances remain unchanged with functional updates
