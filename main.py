import os
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

    result = subprocess.run(
        ["rancid/bin/./rancid-run", group.groups.value],
        capture_output=True,
        text=True,
        stdin=subprocess.DEVNULL,
        check=True
    )
    return result.stdout

@app.get("/health", response_model=Health)
def get_health():
    health = {"health": "healthy"}
    return health


if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=5000, log_level="info")
