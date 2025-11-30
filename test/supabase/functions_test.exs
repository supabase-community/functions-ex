defmodule Supabase.FunctionsTest do
  use ExUnit.Case, async: true

  import Mox

  alias Supabase.Fetcher.Request
  alias Supabase.Functions

  setup :verify_on_exit!

  @mock TestHTTPClient

  setup do
    {:ok, client: Supabase.init_client!("http://127.0.0.1:54321", "test-key")}
  end

  describe "invoke/3" do
    test "successfully invokes a function with default POST method", %{client: client} do
      expect(@mock, :stream, fn request, _opts ->
        assert request.method == :post
        assert request.url.path =~ "/functions/v1/test-function"
        assert Request.get_header(request, "authorization") =~ "Bearer test-key"

        {:ok,
         %Finch.Response{
           status: 200,
           headers: %{"content-type" => "application/json"},
           body: ~s({"message": "success"})
         }}
      end)

      assert {:ok, response} = Functions.invoke(client, "test-function", http_client: @mock)
      assert response.body == %{"message" => "success"}
    end

    test "handles text response content type", %{client: client} do
      expect(@mock, :stream, fn _request, _opts ->
        {:ok,
         %Finch.Response{
           status: 200,
           headers: %{"content-type" => "text/plain"},
           body: "Hello, World!"
         }}
      end)

      assert {:ok, response} = Functions.invoke(client, "test-function", http_client: @mock)
      assert response.body == "Hello, World!"
    end

    test "sets appropriate content-type for binary data", %{client: client} do
      binary_data = <<0, 1, 2, 3>>

      expect(@mock, :stream, fn request, _opts ->
        assert Request.get_header(request, "content-type") == "application/octet-stream"
        assert request.body == binary_data

        {:ok,
         %Finch.Response{
           status: 200,
           headers: %{"content-type" => "application/octet-stream"},
           body: binary_data
         }}
      end)

      assert {:ok, response} =
               Functions.invoke(client, "test-function", body: binary_data, http_client: @mock)

      assert response.body == binary_data
    end

    test "sets appropriate content-type for JSON data", %{client: client} do
      json_data = %{test: "data"}

      expect(@mock, :stream, fn request, _opts ->
        assert Request.get_header(request, "content-type") == "application/json"
        # fetcher will io encode it
        assert {:ok, _} = Jason.decode(request.body)

        {:ok,
         %Finch.Response{
           status: 200,
           headers: %{"content-type" => "application/json"},
           body: ~s({"result": "success"})
         }}
      end)

      assert {:ok, response} =
               Functions.invoke(client, "test-function", body: json_data, http_client: @mock)

      assert response.body == %{"result" => "success"}
    end

    test "handles custom headers", %{client: client} do
      custom_headers = %{"x-custom-header" => "test-value"}

      expect(@mock, :stream, fn request, _opts ->
        assert Request.get_header(request, "x-custom-header") == "test-value"

        {:ok,
         %Finch.Response{
           status: 200,
           headers: %{"content-type" => "application/json"},
           body: ~s({"success": true})
         }}
      end)

      assert {:ok, response} =
               Supabase.Functions.invoke(client, "test-function",
                 headers: custom_headers,
                 http_client: @mock
               )

      assert response.body == %{"success" => true}
    end

    test "handles streaming responses with custom handler", %{client: client} do
      chunks = ["chunk1", "chunk2", "chunk3"]

      expect(@mock, :stream, fn _request, on_response, _opts ->
        Enum.each(chunks, fn chunk ->
          on_response.({200, %{"content-type" => "text/plain"}, [chunk]})
        end)

        {:ok, Enum.join(chunks)}
      end)

      on_response = fn {status, headers, body} ->
        assert status == 200
        assert headers["content-type"] == "text/plain"
        assert is_list(body)
        {:ok, body}
      end

      assert {:ok, response} =
               Functions.invoke(client, "test-function",
                 on_response: on_response,
                 http_client: @mock
               )

      assert response == "chunk1chunk2chunk3"
    end

    test "handles error responses", %{client: client} do
      expect(@mock, :stream, fn _request, _opts ->
        {:ok,
         %Finch.Response{
           status: 404,
           body: ~s({"error": "Function not found"})
         }}
      end)

      assert {:error, error} =
               Functions.invoke(client, "non-existent-function", http_client: @mock)

      assert error.code == :not_found
    end

    test "uses custom HTTP method when specified", %{client: client} do
      expect(@mock, :stream, fn request, _opts ->
        assert request.method == :get

        {:ok,
         %Finch.Response{
           status: 200,
           headers: %{"content-type" => "application/json"},
           body: ~s({"success": true})
         }}
      end)

      assert {:ok, response} =
               Functions.invoke(client, "test-function", method: :get, http_client: @mock)

      assert response.body == %{"success" => true}
    end

    test "handles relay errors", %{client: client} do
      expect(@mock, :stream, fn _request, _opts ->
        {:ok,
         %Finch.Response{
           status: 200,
           headers: %{"content-type" => "application/json", "x-relay-error" => "true"},
           body: ~s({"error": "Relay Error"})
         }}
      end)

      assert {:error, error} =
               Functions.invoke(client, "test-function", http_client: @mock)

      assert error.code == :relay_error
    end

    test "passes timeout option to underlying HTTP client", %{client: client} do
      expect(@mock, :stream, fn _request, opts ->
        assert Keyword.get(opts, :receive_timeout) == 5_000
        assert Keyword.get(opts, :request_timeout) == 5_000

        {:ok,
         %Finch.Response{
           status: 200,
           headers: %{"content-type" => "application/json"},
           body: ~s({"success": true})
         }}
      end)

      assert {:ok, response} =
               Functions.invoke(client, "test-function", timeout: 5_000, http_client: @mock)

      assert response.body == %{"success" => true}
    end

    test "uses default timeout when not specified", %{client: client} do
      expect(@mock, :stream, fn _request, opts ->
        assert Keyword.get(opts, :receive_timeout) == 15_000
        assert Keyword.get(opts, :request_timeout) == 15_000

        {:ok,
         %Finch.Response{
           status: 200,
           headers: %{"content-type" => "application/json"},
           body: ~s({"success": true})
         }}
      end)

      assert {:ok, response} =
               Functions.invoke(client, "test-function", http_client: @mock)

      assert response.body == %{"success" => true}
    end

    test "timeout works with streaming response", %{client: client} do
      chunks = ["chunk1", "chunk2"]

      expect(@mock, :stream, fn _request, on_response, opts ->
        assert Keyword.get(opts, :receive_timeout) == 2_000
        assert Keyword.get(opts, :request_timeout) == 2_000

        Enum.each(chunks, fn chunk ->
          on_response.({200, %{"content-type" => "text/plain"}, [chunk]})
        end)

        {:ok, Enum.join(chunks)}
      end)

      on_response = fn {status, headers, body} ->
        assert status == 200
        assert headers["content-type"] == "text/plain"
        {:ok, body}
      end

      assert {:ok, response} =
               Functions.invoke(client, "test-function",
                 on_response: on_response,
                 timeout: 2_000,
                 http_client: @mock
               )

      assert response == "chunk1chunk2"
    end
  end

  describe "update_auth/2" do
    test "returns a new client with updated access token", %{client: client} do
      new_token = "new_test_token"
      updated_client = Functions.update_auth(client, new_token)

      assert updated_client.access_token == new_token
      # Original client should remain unchanged
      assert client.access_token != new_token
      # All other fields should remain the same
      assert updated_client.base_url == client.base_url
      assert updated_client.api_key == client.api_key
    end

    test "updated client works with invoke/3", %{client: client} do
      new_token = "updated_token"

      expect(@mock, :stream, fn request, _opts ->
        assert Request.get_header(request, "authorization") == "Bearer #{new_token}"

        {:ok,
         %Finch.Response{
           status: 200,
           headers: %{"content-type" => "application/json"},
           body: ~s({"success": true})
         }}
      end)

      updated_client = Functions.update_auth(client, new_token)

      assert {:ok, response} =
               Functions.invoke(updated_client, "test-function", http_client: @mock)

      assert response.body == %{"success" => true}
    end
  end

  describe "auth option in invoke/3" do
    test "overrides authorization header with custom token", %{client: client} do
      custom_token = "custom_auth_token"

      expect(@mock, :stream, fn request, _opts ->
        assert Request.get_header(request, "authorization") == "Bearer #{custom_token}"

        {:ok,
         %Finch.Response{
           status: 200,
           headers: %{"content-type" => "application/json"},
           body: ~s({"authorized": true})
         }}
      end)

      assert {:ok, response} =
               Functions.invoke(client, "test-function", auth: custom_token, http_client: @mock)

      assert response.body == %{"authorized" => true}
    end

    test "works with other options combined", %{client: client} do
      custom_token = "combined_auth_token"
      custom_headers = %{"x-custom" => "value"}
      body_data = %{test: "data"}

      expect(@mock, :stream, fn request, _opts ->
        assert Request.get_header(request, "authorization") == "Bearer #{custom_token}"
        assert Request.get_header(request, "x-custom") == "value"
        assert Request.get_header(request, "content-type") == "application/json"

        {:ok,
         %Finch.Response{
           status: 200,
           headers: %{"content-type" => "application/json"},
           body: ~s({"success": true})
         }}
      end)

      assert {:ok, response} =
               Functions.invoke(client, "test-function",
                 auth: custom_token,
                 headers: custom_headers,
                 body: body_data,
                 http_client: @mock
               )

      assert response.body == %{"success" => true}
    end

    test "original client remains unchanged after auth override", %{client: client} do
      original_token = client.access_token
      custom_token = "temporary_override_token"

      expect(@mock, :stream, fn request, _opts ->
        assert Request.get_header(request, "authorization") == "Bearer #{custom_token}"

        {:ok,
         %Finch.Response{
           status: 200,
           headers: %{"content-type" => "application/json"},
           body: ~s({"success": true})
         }}
      end)

      assert {:ok, _response} =
               Functions.invoke(client, "test-function", auth: custom_token, http_client: @mock)

      # Original client should be unchanged
      assert client.access_token == original_token
    end

    test "nil auth option uses original client token", %{client: client} do
      expect(@mock, :stream, fn request, _opts ->
        assert Request.get_header(request, "authorization") == "Bearer #{client.access_token}"

        {:ok,
         %Finch.Response{
           status: 200,
           headers: %{"content-type" => "application/json"},
           body: ~s({"success": true})
         }}
      end)

      assert {:ok, response} =
               Functions.invoke(client, "test-function", auth: nil, http_client: @mock)

      assert response.body == %{"success" => true}
    end

    test "empty auth option uses original client token", %{client: client} do
      expect(@mock, :stream, fn request, _opts ->
        assert Request.get_header(request, "authorization") == "Bearer #{client.access_token}"

        {:ok,
         %Finch.Response{
           status: 200,
           headers: %{"content-type" => "application/json"},
           body: ~s({"success": true})
         }}
      end)

      assert {:ok, response} = Functions.invoke(client, "test-function", http_client: @mock)
      assert response.body == %{"success" => true}
    end
  end
end
