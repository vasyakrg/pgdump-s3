#!/usr/bin/env python

import os
import sys
from urllib.parse import urlparse

path = os.path.realpath(sys.argv[1])
uri = os.environ['POSTGRESQL_URI']
data = urlparse(uri)
port = data.port or 5432
dbname = data.path[1:]
cmd = 'PGPASSWORD=%s pg_dump -Fc --no-acl --no-owner -h %s -p %s -U %s -f %s %s' % (
    data.password, data.hostname, port, data.username, path,
    dbname
)
print(cmd)
