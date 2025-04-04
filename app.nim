import std/[strformat, strutils, random, times]

import prologue
import db_connector/db_sqlite
import karax/[karaxdsl, vdom]
import ./unlockc

const server* = "https://bodaegl.com"
const qrCreator = "https://cdn.jsdelivr.net/npm/qr-creator/dist/qr-creator.min.js"
const banner = "https://codethecity.org/wp-content/uploads/2018/05/new-data-logo.png"

proc get_db*() : DbCOnn =
  return open("codes.db", "", "", "")

proc randStr*: string =
  let poss = Letters + Digits
  for _ in 0..20:
    result.add(sample(poss))

randomize()
echo randStr()
# const nope = "<h1>nope</h1>"
let
  db = get_db()
if not db.tryExec(sql"SELECT COUNT(*) FROM codes"):
  echo "Creating codes table"
  db.exec(sql"""CREATE TABLE codes (id INTEGER PRIMARY KEY, 
                                    name TEXT NOT NULL, 
                                    code TEXT NOT NULL, 
                                    valid_from DATETIME,
                                    valid_to DATETIME,
                                    created_by TEXT,
                                    created_at DATETIME)""")
if not db.tryExec(sql"SELECT COUNT(*) FROM admin_codes"):
  echo "Creating asmin_codes table"
  db.exec(sql"CREATE TABLE admin_codes (id INTEGER PRIMARY KEY, name TEXT NOT NULL, code TEXT NOT NULL)")
db.close()

template page(inner: untyped) : untyped =
  block:
    let vn = buildhtml(html):
      head:
        title: text "Soap factory lock"
        body:
          img(src=banner)
          h1: text "Soap Factory Door"
          hr()
          inner
    $vn

template nope(ninner: untyped): untyped =
  page:
    h1: text "Nope"
    ninner

const not_allowed = nope:
  p: text "Not allowed"

proc check_code(code:string, admin=false) : (bool, string) =
  let
    db = get_db()
    name = block:
             if admin:
               db.getValue(sql"SELECT name FROM admin_codes WHERE code = ?", code)
             else:
               db.getValue(sql"SELECT name FROM codes WHERE code = ?", code)
  db.close()
  result = (name.len > 0, name)

proc hello*(ctx: Context) {.async.} =
  resp:
    page:
      h1: text "Hello soap factory!"

proc unlock*(ctx: Context) {.async, gcsafe.} =
  let
    ucode = ctx.getPathParams("code", "")
    db = get_db()
    name = db.getValue(sql"SELECT name FROM codes WHERE code = ?", ucode)
    vFrom = db.getValue(sql"SELECT valid_from FROM codes WHERE code = ?", ucode)
    vTo = db.getValue(sql"SELECT valid_to FROM codes WHERE code = ?", ucode)
  db.close()
  if name.len > 0:
    if vFrom.len > 0 or vTo.len > 0:
      try:
        let
          vFromDt = vFrom.parseInt.fromUnix
          vToDt = vTo.parseInt.fromUnix
          n = getTime()
        if n < vFromDt or n > vToDt:
          resp:
            page:
              h1: text "This code isn't valid at this time"
          return
      except Exception as e:
        echo e.msg
        resp:
          nope:
            h1: text "Something went wrong..."
        return
    if ctx.request.reqMethod == HttpPost:
      let (res, msg) = unlock_door()
      if res:
        resp:
          page:
            h1: text "Unlocked"
            p: text "Pull the door and it should open."
            p: text "The door will lock again in 30 seconds."
            p: text "Please ensure the door is locked before you leave."
      else:
        resp:
          page:
            h1: text "Failed"
            p: text msg
    else:
      resp:
        page:
          h1: text "Unlock"
          form(action="#", `method`="post", id="unlock-form"):
            input(`type`="submit", value="unlock")
  else:
    resp(not_allowed, Http403)

proc dtStr(v: string): string =
  result = ""
  try:
    if v.len > 0:
      result = fromUnix(v.parseInt).format("HH:mm d MMM yyyy")
  except Exception as e:
    echo e.msg
    
proc admin*(ctx: Context) {.async.} =
  let
    acode = ctx.getPathParams("code", "")
    db = get_db()
    name = db.getValue(sql"SELECT name FROM admin_codes WHERE code = ?", acode)
    ucodes = db.getAllRows(sql"SELECT name, code, created_by, created_at, valid_from, valid_to FROM codes")
  db.close()
  if len(name) == 0:
    resp(not_allowed, Http403)
  else:
    resp:
      page:
        h1: text "Codes"
        for c in ucodes:
          p:
            a(href=fmt"/admin/detail/{acode}/{c[1]}"): text c[0]
            br()
            text fmt"Created by {c[2]} at {dtStr(c[3])}"
            br()
            if c[4].len > 0 or c[5].len > 0:
              text fmt"Valid from {dtStr(c[4])} to {dtStr(c[5])}"
              br()
            a(href=fmt"/admin/delete/{acode}/{c[1]}"): text "Delete"
        hr()
        a(href=fmt"/admin/create/{acode}"): text "Create new access code"

proc admin_detail*(ctx: Context) {.async.} =
  let
    acode = ctx.getPathParams("acode", "")
    ccode = ctx.getPathParams("ccode", "")
    db = get_db()
    (ok, name) = check_code(acode, true)
    cname = db.getValue(sql"SELECT name FROM codes WHERE code = ?", ccode)
    qrScript = """QrCreator.render({
                  "text": "SERVER/unlock/CODE",
                  "radius": "0.3",
                  "ecLevel": "L",
                  "fill": "#0064a8",
                  "background": "#ffffff",
                  "size": "400"
                  }, 
                  document.querySelector('#qr-code'))""".replace("SERVER", server)
  db.close()
  if not ok:
    resp(not_allowed, Http403)
    return
  resp:
    page:
      h1: text cname
      section(id="qr-code")
      br()
      a(href=fmt"/unlock/{ccode}", class="big-link"):
        text "Unlock link"
      script(src=qrCreator)
      script():
        verbatim(qrScript.replace("CODE", ccode))
      hr()
      a(href=fmt"/admin/{acode}"): text "Admin"
    
      
proc admin_delete*(ctx: Context) {.async.} =
  let
    acode = ctx.getPathParams("acode", "")
    ccode = ctx.getPathParams("ccode", "")
    db = get_db()
    (ok, name) = check_code(acode, true)
  defer: db.close()
  if not ok:
    resp(not_allowed, Http403)
    return
  let res = db.tryExec(sql"DELETE FROM codes WHERE code = ?", ccode)
  if res:
    resp redirect(fmt"/admin/{acode}")
  else:
    resp:
      nope:
        text "failed"
        

proc admin_create*(ctx: Context) {.async.} =
  let
    acode = ctx.getPathParams("code", "")
    db = get_db()
    (ok, name) = check_code(acode, true)
  defer: db.close()
  if not ok:
    resp(not_allowed, Http403)
    return
  if ctx.request.reqMethod == HttpPost:
    randomize()
    let
      cname = ctx.getFormParams("name", "")
      ccode = randStr()
    var
      vFrom = ctx.getFormParams("valid-from", "")
      vTo = ctx.getFormParams("valid-to", "")
    try:
      vFrom = $vFrom.parseTime("yyyy-MM-dd'T'HH:mm", utc()).toUnix()
      vTo = $vTo.parseTime("yyyy-MM-dd'T'HH:mm", utc()).toUnix()
    except Exception as e:
      echo e.msg
        
    if name.len == 0:
      resp:
        nope:
          h3: text "Name is required"
      return
    db.exec(sql"""INSERT INTO codes (name, code, created_by, created_at, valid_from, valid_to) 
                   VALUES (?, ?, ?, ?, ?, ?)""",
            cname, ccode, name, now().toTime.toUnix, vFrom, vTo)
    resp redirect(fmt"/admin/detail/{acode}/{ccode}")
    return
  else:
    resp:
      page:
        h1: text "Create new permanent code"
        form(action="#", `method`="post"):
          input(name="name")
          br()
          input(`type`="submit",value="create")
        hr()
        h1: text "Create new time based code"
        form(action="#", `method`="post"):
          input(name="name")
          br()
          label(`for`="valid-from"):
            text "Valid from"
          input(`type`="datetime-local", name="valid-from")
          br()
          label(`for`="vlaid-to"):
            text "Valid until"
          input(`type`="datetime-local", name="valid-to")
          br()
          input(`type`="submit", value="create")

when isMainModule:  
  let app = newApp()
  app.get("/", hello)
  # app.get("/logo.png", logo)
  app.addRoute("/unlock/{code}", unlock, @[HttpGet, HttpPost])
  app.get("/admin/{code}", admin)
  app.get("/admin/delete/{acode}/{ccode}", admin_delete)
  app.get("/admin/detail/{acode}/{ccode}", admin_detail)
  app.addRoute("/admin/create/{code}", admin_create, @[HttpGet, HttpPost])
  app.run()
