from fastapi import Depends, HTTPException, status
from app.routes.auth import get_current_user
from app.models.user import User

def role_checker(allowed_roles: list[str]):
    def checker(current_user: User = Depends(get_current_user)):
        if current_user.role not in allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Недостаточно прав для выполнения этого действия"
            )
        return current_user
    return checker
