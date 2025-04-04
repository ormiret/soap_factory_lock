import std/[osproc, json, strformat]


proc unlock_door*(): (bool, string) = 
  try:
    let
      outp = execProcess("uv -q run unlock.py")
      jsn = parseJson(outp)
      res = jsn["result"].getBool()
      msg = jsn["message"].getStr()
    return (res, msg)
  except Exception as e:
    return (false, e.msg)
    
when isMainModule:
  echo $unlock_door()
