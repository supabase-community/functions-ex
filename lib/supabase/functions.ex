defmodule Supabase.Functions do
  @moduledoc """
  This module provides integration with the Supabase Edge Functions API, enabling developers
  to invoke their serverless functions.

  ## Usage

      iex> client = Supabase.init_client!("SUPABASE_URL", "SUPABASE_KEY")
      iex> Supabase.Functions.invoke(client, "function_name", %{})
  """

  alias Supabase.Client
  alias Supabase.Fetcher
  alias Supabase.Fetcher.Request
  alias Supabase.Fetcher.Response

  @type opts :: Enumerable.t(opt)

  @typedoc """
  Available options for invoking a function:

  - `body`: The body of the request.
  - `headers`: The additional custom headers of the request.
  - `method`: The HTTP method of the request.
  - `region`: The Region to invoke the function in.
  - `on_response`: The custom response handler for response streaming.
  - `timeout`: The timeout in milliseconds for the request. Defaults to 15 seconds.
  - `access_token`: Override the authorization token for this request.
  """
  @type opt ::
          {:body, Fetcher.body()}
          | {:headers, Fetcher.headers()}
          | {:method, Fetcher.method()}
          | {:region, region}
          | {:on_response, on_response}
          | {:timeout, pos_integer()}
          | {:access_token, String.t()}

  @type on_response :: ({Fetcher.status(), Fetcher.headers(), body :: Enumerable.t()} ->
                          Supabase.result(Response.t()))

  @type region ::
          :any
          | :"us-west-1"
          | :"us-west-2"
          | :"us-east-1"
          | :"eu-west-1"
          | :"eu-west-2"
          | :"eu-west-3"
          | :"ap-south-1"
          | :"ap-southeast-1"
          | :"ap-southeast-2"
          | :"ap-northeast-1"
          | :"ap-northeast-2"
          | :"sa-east-1"
          | :"ca-central-1"
          | :"eu-central-1"

  @doc """
  Updates the access token for a client

  Creates a new client instance with the updated access token. This provides
  feature parity with the JavaScript client's `setAuth(token)` method.

  ## Examples

      # Update auth token functionally
      new_client = Supabase.Functions.update_auth(client, "new_token")
      {:ok, response} = Supabase.Functions.invoke(new_client, "my-function")

  """
  @spec update_auth(Client.t(), String.t()) :: Client.t()
  def update_auth(%Client{} = client, token) when is_binary(token) do
    %{client | access_token: token}
  end

  @doc """
  Invokes a function

  Invoke a Supabase Edge Function.

  - When you pass in a body to your function, we automatically attach the `Content-Type` header automatically. If it doesn't match any of these types we assume the payload is json, serialize it and attach the `Content-Type` header as `application/json`. You can override this behavior by passing in a `Content-Type` header of your own.
  - Responses are automatically parsed as json depending on the Content-Type header sent by your function. Responses are parsed as text by default.

  ## Authentication

  You can override the authorization token for a specific request using the `access_token` option:

      # Use a different token for this request
      {:ok, response} = Supabase.Functions.invoke(client, "my-function", access_token: "new_token")

  Alternatively, you can update the client's auth token functionally:

      # Update the client's token
      new_client = Supabase.Functions.update_auth(client, "new_token")
      {:ok, response} = Supabase.Functions.invoke(new_client, "my-function")

  ## Timeout Support

  You can set a timeout for function invocations using the `timeout` option. This sets both the 
  receive timeout (for individual chunks) and request timeout (for the complete response):

      # Timeout after 5 seconds
      Supabase.Functions.invoke(client, "my-function", timeout: 5_000)
      
  If no timeout is specified, requests will timeout after 15 seconds by default.

  ## Examples

      # Basic invocation
      {:ok, response} = Supabase.Functions.invoke(client, "my-function")
      
      # With timeout
      {:ok, response} = Supabase.Functions.invoke(client, "my-function", timeout: 10_000)
      
      # With body and timeout  
      {:ok, response} = Supabase.Functions.invoke(client, "my-function", 
        body: %{data: "value"}, 
        timeout: 30_000)

      # With custom access token
      {:ok, response} = Supabase.Functions.invoke(client, "my-function", access_token: "custom_token")
  """
  @spec invoke(Client.t(), function :: String.t(), opts) :: Supabase.result(Response.t())
  def invoke(%Client{} = client, name, opts \\ []) when is_binary(name) do
    method = opts[:method] || :post
    custom_headers = opts[:headers] || %{}
    timeout = opts[:timeout] || 15_000

    effective_client =
      if opts[:access_token] do
        update_auth(client, opts[:access_token])
      else
        client
      end

    effective_client
    |> Request.new(decode_body?: false)
    |> Request.with_functions_url(name)
    |> Request.with_method(method)
    |> maybe_define_region(opts[:region])
    |> then(&if body = opts[:body], do: Request.with_body(&1, body), else: &1)
    |> then(&if c = opts[:http_client], do: Request.with_http_client(&1, c), else: &1)
    |> Request.with_body_decoder(nil)
    |> maybe_define_content_type(opts[:body])
    |> Request.with_headers(custom_headers)
    |> execute_request(opts[:on_response], timeout)
    |> maybe_decode_body()
    |> handle_response()
  end

  defp maybe_define_region(req, nil), do: req
  defp maybe_define_region(req, :any), do: req

  defp maybe_define_region(req, region) do
    Request.with_headers(req, %{"x-region" => region})
  end

  defp maybe_define_content_type(req, nil), do: req

  defp maybe_define_content_type(req, string) when is_binary(string) do
    if raw_binary?(string) do
      Request.with_headers(req, %{"content-type" => "application/octet-stream"})
    else
      Request.with_headers(req, %{"content-type" => "text/plain"})
    end
  end

  defp maybe_define_content_type(req, %{}) do
    Request.with_headers(req, %{"content-type" => "application/json"})
  end

  defp raw_binary?(bin), do: not String.printable?(bin)

  defp execute_request(req, on_response, timeout) do
    opts = [receive_timeout: timeout, request_timeout: timeout]

    if on_response do
      Fetcher.stream(req, on_response, opts)
    else
      Fetcher.stream(req, nil, opts)
    end
  end

  defp maybe_decode_body(:ok), do: :ok
  defp maybe_decode_body({:error, _} = err), do: err

  defp maybe_decode_body({:ok, %Response{} = resp}) do
    content_type = Response.get_header(resp, "content-type") || "text/plain"
    decoder = decoder_from_content_type(content_type)

    with {:ok, body} <- decoder.(resp.body), do: {:ok, %{resp | body: body}}
  end

  defp maybe_decode_body({:ok, _body} = ok), do: ok

  defp decoder_from_content_type("application/json"), do: &JSON.decode/1

  defp decoder_from_content_type(_) do
    fn body -> {:ok, Function.identity(body)} end
  end

  defp handle_response({:ok, %Response{} = resp}) do
    if Response.get_header(resp, "x-relay-error") == "true" do
      {:error,
       Supabase.Error.new(
         service: :functions,
         code: :relay_error,
         message: "Relay Error invoking the Edge Function",
         metadata: resp
       )}
    else
      {:ok, resp}
    end
  end

  defp handle_response(other), do: other
end
