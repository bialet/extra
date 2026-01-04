//
// This file is part of Bialet, which is licensed under the
// MIT License.
//
// Copyright (c) 2023-2026 Rodrigo Arce
//
// SPDX-License-Identifier: MIT
//
// For full license text, see LICENSE.md.

class Mcp {
  construct new(name, version) {
    _name = name
    _version = version
    _tools = []
    _toolsMap = {}
    _prompts = []
  }
  addPrompt(prompt) {
    _prompts.add(prompt)
    return this
  }
  addTool(toolClass) {
    _tools.add(toolClass)
    _toolsMap[camelCase(toolClass.name)] = toolClass
    return this
  }
  serve {
    // MCP uses JSON-RPC 2.0 over HTTP - all requests come to /mcp
    // The method is specified in the JSON body, not the URL path
    if (!Request.isPost) {
      // Only POST requests are valid for JSON-RPC
      return Response.json({
        "name": _name,
        "version": _version,
        "protocol": "MCP over JSON-RPC 2.0"
      })
    }
    // Parse JSON-RPC request
    var request = null
    if (Request.body != null && Request.body != "") {
      request = Json.parse(Request.body)
    } else {
      return jsonRpcError(null, -32700, "Parse error", "Empty request body")
    }
    // Validate JSON-RPC structure
    if (request["jsonrpc"] != "2.0") {
      return jsonRpcError(request["id"], -32600, "Invalid Request", "Missing or invalid jsonrpc version")
    }
    var method = request["method"]
    var params = request["params"]
    var id = request["id"]
    // Handle JSON-RPC methods
    if (method == "initialize") {
      return initialize(id, params)
    } else if (method == "notifications/initialized") {
      return notificationsInitialized()
    } else if (method == "tools/list") {
      return listTools(id, params)
    } else if (method == "tools/call") {
      return callTool(id, params)
    } else if (method == "prompts/list") {
      return listPrompts(id, params)
    } else {
      return jsonRpcError(id, -32601, "Method not found", "Unknown method: %(method)")
    }
  }
  jsonRpcError(id, code, message, data) {
    Response.json({
      "jsonrpc": "2.0",
      "id": id,
      "error": {
        "code": code,
        "message": message,
        "data": data
      }
    })
  }
  jsonRpcResponse(id, result) {
    Response.json({
      "jsonrpc": "2.0",
      "id": id,
      "result": result
    })
  }
  initialize(id, params) {
    // params may contain clientInfo with name and version
    jsonRpcResponse(id, {
      "protocolVersion": "2024-11-05",
      "capabilities": {
        "tools": {},
        "prompts": {}
      },
      "serverInfo": {
        "name": _name,
        "version": _version
      }
    })
  }
  notificationsInitialized() { Response.status(204) }
  listTools(id, params) {
    var tools = []
    for (toolClass in _tools) {
      // Get class-level attributes
      var classAttrs = toolClass.attributes.self
      var description = ""
      // Attributes are nested - the key is an empty string
      if (classAttrs is Map) {
        for (key in classAttrs.keys) {
          var attrs = classAttrs[key]
          if (attrs is Map && attrs.containsKey("doc") && attrs["doc"] is List && attrs["doc"].count > 0) {
            description = attrs["doc"][0]
          }
        }
      }
      var tool = {
        "name": camelCase(toolClass.name),
        "description": description,
        "inputSchema": {
          "type": "object",
          "properties": {},
          "required": []
        }
      }
      // Build properties from method attributes
      var methods = toolClass.attributes.methods
      if (methods is Map) {
        for (methodName in methods.keys) {
          var methodData = methods[methodName]
          if (methodName != "call()") {
            // Remove parentheses from method name
            var propName = methodName.replace("(_)", "")
            var property = {}
            // Method attributes are also nested with empty string key
            if (methodData is Map) {
              for (key in methodData.keys) {
                var methodAttrs = methodData[key]
                if (methodAttrs is Map) {
                  if (methodAttrs.containsKey("doc") && methodAttrs["doc"] is List && methodAttrs["doc"].count > 0) {
                    property["description"] = methodAttrs["doc"][0]
                  }
                  if (methodAttrs.containsKey("type") && methodAttrs["type"] is List && methodAttrs["type"].count > 0) {
                    var typeStr = methodAttrs["type"][0].toString
                    property["type"] = typeStr.lower
                  } else {
                    property["type"] = "string" // Default type
                  }
                  if (methodAttrs.containsKey("format") && methodAttrs["format"] is List && methodAttrs["format"].count > 0) {
                    property["format"] = methodAttrs["format"][0]
                  }
                  // Check if required attribute exists (it appears as an empty list when present)
                  if (methodAttrs.containsKey("required")) {
                    tool["inputSchema"]["required"].add(propName)
                  }
                }
              }
            }
            tool["inputSchema"]["properties"][propName] = property
          }
        }
      }
      tools.add(tool)
    }
    jsonRpcResponse(id, {
      "tools": tools
    })
  }
  listPrompts(id, params) {
    var prompts = []
    for (prompt in _prompts) {
      prompts.add({
        "name": "default",
        "description": prompt
      })
    }
    jsonRpcResponse(id, {
      "prompts": prompts
    })
  }
  callTool(id, params) {
    var toolName = params["name"]
    var arguments = params["arguments"]
    // Find the tool class using the map
    if (_toolsMap.containsKey(toolName)) {
      var toolClass = _toolsMap[toolName]
      // Create instance based on tool name
      var instance = toolClass.new(arguments)
      // Call the tool
      var result = instance.call()
      jsonRpcResponse(id, {
        "content": [
          {
            "type": "text",
            "text": result.toString
          }
        ]
      })
      return
    }
    jsonRpcError(id, -32602, "Tool not found", toolName)
  }
  camelCase(str) {
    if (str.count == 0) return str
    return str[0].lower + str[1..-1]
  }
}
