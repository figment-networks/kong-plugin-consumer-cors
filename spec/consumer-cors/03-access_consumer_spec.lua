local helpers = require "spec.helpers"

local PLUGIN_NAME = "consumer-cors"
local CORS_DEFAULT_METHODS = "GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS,TRACE,CONNECT"
local AUTH_KEY = "kong_auth"

for _, strategy in helpers.each_strategy() do
  describe("Plugin: cors (access) [#" .. strategy .. "]", function()
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, nil, { "error-generator-last", PLUGIN_NAME })

      local upstream = bp.upstreams:insert({
        name = "cors.com",
      })

      bp.targets:insert {
        target = helpers.mock_upstream_host .. ':' .. helpers.mock_upstream_port,
        weight = 1000,
        upstream = { id = upstream.id },
      }

      local service = bp.services:insert {
        name = "http",
        host = upstream.name,
        port = helpers.mock_upstream_port,
        protocol = helpers.mock_upstream_protocol,
      }

      bp.routes:insert {
        protocols = { "http" },
        hosts = { upstream.name },
        name = "http-route",
        paths = { "/" },
        service = service,
      }

      bp.plugins:insert {
        name = "key-auth",
        service = { id = service.id },
        config = {
          key_names =  { "apikey", "Authorization", "X-Api-Key" },
          hide_credentials = false,
        }
      }

      local consumer = bp.consumers:insert {
        username = "bob"
      }

      bp.keyauth_credentials:insert {
        key      = AUTH_KEY,
        consumer = { id = consumer.id },
      }

      bp.plugins:insert {
        name = PLUGIN_NAME,
        consumer = { id = consumer.id },
        config = {
          origins            = { "cors.com" },
        }
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled,error-generator-last," .. PLUGIN_NAME,
      }))

    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then proxy_client:close() end
    end)

    describe("HTTP method: OPTIONS", function()
      it("gives appropriate defaults", function()
        local res = assert(proxy_client:send {
          method  = "OPTIONS",
          headers = {
            ["Host"] = "cors.com",
            ["Origin"] = "origin1.com",
            ["Access-Control-Request-Method"] = "GET",
            ["X-Api-Key"] = AUTH_KEY,
          }
        })
        assert.res_status(200, res)
        assert.equal("0", res.headers["Content-Length"])
        assert.equal(CORS_DEFAULT_METHODS, res.headers["Access-Control-Allow-Methods"])
        assert.equal("cors.com", res.headers["Access-Control-Allow-Origin"])
        assert.is_nil(res.headers["Access-Control-Allow-Headers"])
        assert.is_nil(res.headers["Access-Control-Expose-Headers"])
        assert.is_nil(res.headers["Access-Control-Allow-Credentials"])
        assert.is_nil(res.headers["Access-Control-Max-Age"])
        assert.equal("Origin", res.headers["Vary"])
      end)
    end)
  end)
end
