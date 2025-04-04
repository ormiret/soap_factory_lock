import std/[strformat, os]

import db_connector/db_sqlite

import ./app

proc make_admin(name: string): string =
  let
    db = get_db()
    code = randStr()
  db.exec(sql"INSERT INTO admin_codes (name, code) VALUES (?, ?)", name, code)
  return fmt"{server}/admin/{code}"
  
when isMainModule:
  let args = commandLineParams()
  if len(args) != 1:
    echo fmt"usage: {getAppFilename()} <name>"
    quit -1
  else:
    echo make_admin(args[0])
