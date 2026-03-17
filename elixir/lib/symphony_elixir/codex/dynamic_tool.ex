defmodule SymphonyElixir.Codex.DynamicTool do
  @moduledoc """
  Executes client-side tool calls requested by Codex app-server turns.
  """

  alias SymphonyElixir.Config
  alias SymphonyElixir.Linear.Client

  @linear_graphql_tool "linear_graphql"
  @linear_graphql_description """
  Execute a raw GraphQL query or mutation against Linear using Symphony's configured auth.
  """
  @linear_graphql_input_schema %{
    "type" => "object",
    "additionalProperties" => false,
    "required" => ["query"],
    "properties" => %{
      "query" => %{
        "type" => "string",
        "description" => "GraphQL query or mutation document to execute against Linear."
      },
      "variables" => %{
        "type" => ["object", "null"],
        "description" => "Optional GraphQL variables object.",
        "additionalProperties" => true
      }
    }
  }

  @plane_rest_tool "plane_rest"
  @plane_rest_description "Execute a Plane REST API call using Symphony's configured Plane auth."
  @plane_rest_input_schema %{
    "type" => "object",
    "required" => ["method", "path"],
    "properties" => %{
      "method" => %{
        "type" => "string",
        "enum" => ["GET", "POST", "PATCH", "DELETE"]
      },
      "path" => %{
        "type" => "string",
        "description" => "Path relative to workspace base URL, must start with /"
      },
      "body" => %{
        "type" => ["object", "null"],
        "description" => "Request body for POST/PATCH"
      }
    }
  }

  @spec execute(String.t() | nil, term(), keyword()) :: map()
  def execute(tool, arguments, opts \\ []) do
    case tool do
      @linear_graphql_tool ->
        execute_linear_graphql(arguments, opts)

      @plane_rest_tool ->
        execute_plane_rest(arguments, opts)

      other ->
        failure_response(%{
          "error" => %{
            "message" => "Unsupported dynamic tool: #{inspect(other)}.",
            "supportedTools" => supported_tool_names()
          }
        })
    end
  end

  @spec tool_specs() :: [map()]
  def tool_specs do
    case Config.tracker_kind() do
      "linear" ->
        [linear_graphql_spec()]

      "plane" ->
        [plane_rest_spec()]

      _ ->
        [linear_graphql_spec(), plane_rest_spec()]
    end
  end

  # ---------------------------------------------------------------------------
  # linear_graphql
  # ---------------------------------------------------------------------------

  defp execute_linear_graphql(arguments, opts) do
    linear_client = Keyword.get(opts, :linear_client, &Client.graphql/3)

    with {:ok, query, variables} <- normalize_linear_graphql_arguments(arguments),
         {:ok, response} <- linear_client.(query, variables, []) do
      graphql_response(response)
    else
      {:error, reason} ->
        failure_response(tool_error_payload(reason))
    end
  end

  defp normalize_linear_graphql_arguments(arguments) when is_binary(arguments) do
    case String.trim(arguments) do
      "" -> {:error, :missing_query}
      query -> {:ok, query, %{}}
    end
  end

  defp normalize_linear_graphql_arguments(arguments) when is_map(arguments) do
    case normalize_query(arguments) do
      {:ok, query} ->
        case normalize_variables(arguments) do
          {:ok, variables} ->
            {:ok, query, variables}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_linear_graphql_arguments(_arguments), do: {:error, :invalid_arguments}

  defp normalize_query(arguments) do
    case Map.get(arguments, "query") || Map.get(arguments, :query) do
      query when is_binary(query) ->
        case String.trim(query) do
          "" -> {:error, :missing_query}
          trimmed -> {:ok, trimmed}
        end

      _ ->
        {:error, :missing_query}
    end
  end

  defp normalize_variables(arguments) do
    case Map.get(arguments, "variables") || Map.get(arguments, :variables) || %{} do
      variables when is_map(variables) -> {:ok, variables}
      _ -> {:error, :invalid_variables}
    end
  end

  defp graphql_response(response) do
    success =
      case response do
        %{"errors" => errors} when is_list(errors) and errors != [] -> false
        %{errors: errors} when is_list(errors) and errors != [] -> false
        _ -> true
      end

    %{
      "success" => success,
      "contentItems" => [
        %{
          "type" => "inputText",
          "text" => encode_payload(response)
        }
      ]
    }
  end

  # ---------------------------------------------------------------------------
  # plane_rest
  # ---------------------------------------------------------------------------

  defp execute_plane_rest(arguments, opts) do
    if Config.tracker_kind() != "plane" do
      failure_response(%{
        "error" => %{
          "message" => "plane_rest is only available when tracker.kind is \"plane\"."
        }
      })
    else
      plane_client = Keyword.get(opts, :plane_client, &default_plane_client/3)

      with {:ok, method, path, body} <- normalize_plane_rest_arguments(arguments) do
        base_url = Config.plane_base_url()
        url = base_url <> String.trim_leading(path, "/")
        token = Config.plane_api_token()

        case plane_client.(method, url, %{body: body, token: token}) do
          {:ok, %{status: status, body: resp_body}} when status in 200..299 ->
            %{
              "success" => true,
              "contentItems" => [
                %{
                  "type" => "inputText",
                  "text" => encode_payload(resp_body)
                }
              ]
            }

          {:ok, response} ->
            failure_response(%{
              "error" => %{
                "message" => "Plane REST request failed with HTTP #{response.status}.",
                "status" => response.status
              }
            })

          {:error, reason} ->
            failure_response(%{
              "error" => %{
                "message" => "Plane REST request failed.",
                "reason" => inspect(reason)
              }
            })
        end
      else
        {:error, reason} ->
          failure_response(plane_tool_error_payload(reason))
      end
    end
  end

  defp normalize_plane_rest_arguments(arguments) when is_map(arguments) do
    method = Map.get(arguments, "method") || Map.get(arguments, :method)
    path = Map.get(arguments, "path") || Map.get(arguments, :path)
    body = Map.get(arguments, "body") || Map.get(arguments, :body)

    cond do
      not is_binary(method) or String.trim(method) == "" ->
        {:error, :missing_method}

      method not in ["GET", "POST", "PATCH", "DELETE"] ->
        {:error, {:invalid_method, method}}

      not is_binary(path) or String.trim(path) == "" ->
        {:error, :missing_path}

      true ->
        {:ok, method_to_atom(method), path, body}
    end
  end

  defp normalize_plane_rest_arguments(_arguments), do: {:error, :invalid_arguments}

  defp default_plane_client(method, url, %{body: body, token: token}) do
    headers = [
      {"X-Api-Key", token || ""},
      {"Content-Type", "application/json"}
    ]

    opts = [headers: headers, connect_options: [timeout: 30_000]]

    case method do
      :get -> Req.get(url, opts)
      :post -> Req.post(url, Keyword.put(opts, :json, body))
      :patch -> Req.patch(url, Keyword.put(opts, :json, body))
      :delete -> Req.delete(url, opts)
    end
  end

  defp method_to_atom("GET"), do: :get
  defp method_to_atom("POST"), do: :post
  defp method_to_atom("PATCH"), do: :patch
  defp method_to_atom("DELETE"), do: :delete

  defp plane_tool_error_payload(:missing_method) do
    %{"error" => %{"message" => "`plane_rest` requires a `method` string (GET, POST, PATCH, DELETE)."}}
  end

  defp plane_tool_error_payload({:invalid_method, method}) do
    %{"error" => %{"message" => "`plane_rest` method must be GET, POST, PATCH, or DELETE. Got: #{inspect(method)}."}}
  end

  defp plane_tool_error_payload(:missing_path) do
    %{"error" => %{"message" => "`plane_rest` requires a non-empty `path` string starting with /."}}
  end

  defp plane_tool_error_payload(:invalid_arguments) do
    %{"error" => %{"message" => "`plane_rest` expects an object with `method` and `path`."}}
  end

  defp plane_tool_error_payload(reason) do
    %{"error" => %{"message" => "plane_rest tool execution failed.", "reason" => inspect(reason)}}
  end

  # ---------------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------------

  defp failure_response(payload) do
    %{
      "success" => false,
      "contentItems" => [
        %{
          "type" => "inputText",
          "text" => encode_payload(payload)
        }
      ]
    }
  end

  defp encode_payload(payload) when is_map(payload) or is_list(payload) do
    Jason.encode!(payload, pretty: true)
  end

  defp encode_payload(payload), do: inspect(payload)

  defp tool_error_payload(:missing_query) do
    %{
      "error" => %{
        "message" => "`linear_graphql` requires a non-empty `query` string."
      }
    }
  end

  defp tool_error_payload(:invalid_arguments) do
    %{
      "error" => %{
        "message" => "`linear_graphql` expects either a GraphQL query string or an object with `query` and optional `variables`."
      }
    }
  end

  defp tool_error_payload(:invalid_variables) do
    %{
      "error" => %{
        "message" => "`linear_graphql.variables` must be a JSON object when provided."
      }
    }
  end

  defp tool_error_payload(:missing_linear_api_token) do
    %{
      "error" => %{
        "message" => "Symphony is missing Linear auth. Set `linear.api_key` in `WORKFLOW.md` or export `LINEAR_API_KEY`."
      }
    }
  end

  defp tool_error_payload({:linear_api_status, status}) do
    %{
      "error" => %{
        "message" => "Linear GraphQL request failed with HTTP #{status}.",
        "status" => status
      }
    }
  end

  defp tool_error_payload({:linear_api_request, reason}) do
    %{
      "error" => %{
        "message" => "Linear GraphQL request failed before receiving a successful response.",
        "reason" => inspect(reason)
      }
    }
  end

  defp tool_error_payload(reason) do
    %{
      "error" => %{
        "message" => "Linear GraphQL tool execution failed.",
        "reason" => inspect(reason)
      }
    }
  end

  defp linear_graphql_spec do
    %{
      "name" => @linear_graphql_tool,
      "description" => @linear_graphql_description,
      "inputSchema" => @linear_graphql_input_schema
    }
  end

  defp plane_rest_spec do
    %{
      "name" => @plane_rest_tool,
      "description" => @plane_rest_description,
      "inputSchema" => @plane_rest_input_schema
    }
  end

  defp supported_tool_names do
    Enum.map(tool_specs(), & &1["name"])
  end
end
