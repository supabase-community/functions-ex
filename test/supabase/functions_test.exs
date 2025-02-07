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
      expect(@mock, :stream, fn _request, _ ->
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

      expect(@mock, :stream, fn request, _ ->
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

      expect(@mock, :stream, fn request, _ ->
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

      expect(@mock, :stream, fn request, _ ->
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

      expect(@mock, :stream, fn _request, on_response, _ ->
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
      expect(@mock, :stream, fn _request, _ ->
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
      expect(@mock, :stream, fn request, _ ->
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
  end
end
