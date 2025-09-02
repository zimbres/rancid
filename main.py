import os
import pty
import subprocess
from enum import Enum

import uvicorn
from fastapi import Depends, FastAPI
from pydantic import BaseModel

groups_env = os.environ["GROUPS"].split(",")
Groups = Enum("Groups", {g: g for g in groups_env})

app = FastAPI()

class Health(BaseModel):
    health: str

class Group(BaseModel):
    groups: Groups = groups_env[0]

@app.post("/execute")
def execute(group: Group = Depends()):
    master_fd, slave_fd = pty.openpty()
    result = subprocess.run(
        ["rancid/bin/./rancid-run", group.groups.value],
        stdout=slave_fd,
        stderr=slave_fd,
        stdin=slave_fd,
        text=True
    )
    os.close(slave_fd)
    os.close(master_fd)
    return result.stdout

@app.get("/health", response_model=Health)
def get_health():
    health = {"health": "healthy"}
    return health


if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=5000, log_level="info")
