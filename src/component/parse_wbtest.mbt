///|
test "parse component type alias export" {
  let name = @utf8.encode("foo")
  let bytes : Array[Byte] = []
  bytes.push(0x03U.to_byte()) // type
  bytes.push(0x00U.to_byte()) // export target
  bytes.push(0x00U.to_byte()) // instance index 0
  bytes.push(0x03U.to_byte()) // name length
  for b in name {
    bytes.push(b)
  }
  let parser = Parser::new(Bytes::from_array(bytes))
  let entry = parse_component_type_alias(parser)
  match entry {
    InstanceTypeEntry::Alias(InstanceAliasTarget::Export(idx, alias_name)) => {
      assert_eq(idx, 0U)
      assert_eq(alias_name, name)
    }
    _ => fail("expected export alias")
  }
}

///|
test "parse sync func type (0x40)" {
  let bytes : Array[Byte] = []
  bytes.push(0x40U.to_byte()) // sync func
  bytes.push(0x01U.to_byte()) // 1 param
  bytes.push(0x01U.to_byte()) // name length 1
  bytes.push(0x78U.to_byte()) // "x"
  bytes.push(0x7AU.to_byte()) // s32
  bytes.push(0x00U.to_byte()) // single result
  bytes.push(0x7AU.to_byte()) // s32
  let parser = Parser::new(Bytes::from_array(bytes))
  let ty = parse_component_type(parser)
  match ty {
    ComponentTypeDef::Func(f) => {
      assert_eq(f.is_async, false)
      assert_eq(f.params.length(), 1)
      assert_eq(f.results.length(), 1)
    }
    _ => fail("expected Func")
  }
}

///|
test "parse async func type (0x43)" {
  let bytes : Array[Byte] = []
  bytes.push(0x43U.to_byte()) // async func
  bytes.push(0x02U.to_byte()) // 2 params
  bytes.push(0x06U.to_byte()) // name length 6
  for b in b"method" {
    bytes.push(b)
  }
  bytes.push(0x73U.to_byte()) // string
  bytes.push(0x03U.to_byte()) // name length 3
  for b in b"url" {
    bytes.push(b)
  }
  bytes.push(0x73U.to_byte()) // string
  bytes.push(0x00U.to_byte()) // single result
  bytes.push(0x78U.to_byte()) // s64
  let parser = Parser::new(Bytes::from_array(bytes))
  let ty = parse_component_type(parser)
  match ty {
    ComponentTypeDef::Func(f) => {
      assert_eq(f.is_async, true)
      assert_eq(f.params.length(), 2)
      assert_eq(f.results.length(), 1)
    }
    _ => fail("expected Func")
  }
}

///|
test "parse component type alias outer" {
  let bytes : Array[Byte] = []
  bytes.push(0x03U.to_byte()) // type
  bytes.push(0x02U.to_byte()) // outer target
  bytes.push(0x01U.to_byte()) // count
  bytes.push(0x02U.to_byte()) // index
  let parser = Parser::new(Bytes::from_array(bytes))
  let entry = parse_component_type_alias(parser)
  match entry {
    InstanceTypeEntry::Alias(InstanceAliasTarget::Outer(count, index)) => {
      assert_eq(count, 1U)
      assert_eq(index, 2U)
    }
    _ => fail("expected outer alias")
  }
}
