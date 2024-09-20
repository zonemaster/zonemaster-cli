{
  "net":{
    "ipv4": false,
    "ipv6": false
  },
  "resolver":{
    "source4": "192.0.2.1",
    "source6": "2001:db8::1"
  },
  "test_levels" : {
    "BASIC" : {
      "B01_CHILD_FOUND" : "NOTICE",
      "B01_ROOT_HAS_NO_PARENT" : "WARNING",
      "B02_AUTH_RESPONSE_SOA" : "ERROR"
    },
    "SYSTEM" : {
      "GLOBAL_VERSION" : "INFO"
    }
  }
}
