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
