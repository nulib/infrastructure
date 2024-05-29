from pg8000.native import Connection

def handler(event, _context):
  config = event['connection']
  conn = Connection(**config)
  for table in event.get('tables', []):
    conn.run(f"DELETE FROM {table} WHERE updated_at < NOW() - interval '1 WEEK'")
    conn.run(f"VACUUM {table}")