"""RFC 7807 problem+json — one error shape app-wide."""
from fastapi import Request
from fastapi.responses import JSONResponse


class AppError(Exception):
    def __init__(self, status: int, title: str, detail: str | None = None,
                 type_: str = "about:blank"):
        self.status = status
        self.title = title
        self.detail = detail
        self.type = type_


def problem(status: int, title: str, detail: str | None = None,
            type_: str = "about:blank") -> JSONResponse:
    body = {"type": type_, "title": title, "status": status}
    if detail:
        body["detail"] = detail
    return JSONResponse(status_code=status, content=body,
                        media_type="application/problem+json")


async def app_error_handler(_: Request, exc: AppError) -> JSONResponse:
    return problem(exc.status, exc.title, exc.detail, exc.type)
