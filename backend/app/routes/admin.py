"""
Admin API Routes
Faqat admin foydalanuvchilar uchun maxsus endpointlar
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import func, text
from typing import List, Dict, Any
from datetime import datetime, timedelta
import os
import re
import subprocess
import json

from app.db.session import get_db
from app.dependencies import get_current_user
from app.models.user import User
from app.models.order import Order
from app.models.equipment import Equipment
from app.models.balance import Balance, BalanceTransaction
from app.schemas.user import UserRead

router = APIRouter()

# ============================================================================
# Helper Functions
# ============================================================================

def check_admin_permission(current_user: User):
    """Admin ekanligini tekshirish"""
    if current_user.role != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only admin users can access this endpoint"
        )

#: Backup fayl nomi: backup_<sana>_<vaqt>.sql yoki .sql.gz
BACKUP_FILENAME_RE = re.compile(r"^backup_[A-Za-z0-9_\-]+\.sql(\.gz)?$")


def safe_backup_filename(filename: str) -> str:
    """
    Backup fayl nomini tekshiradi.

    Hozir Starlette yo'ldagi kodlangan sleshni o'tkazmaydi, ya'ni
    "../.." bilan papkadan chiqib bo'lmaydi. Lekin bazani tiklash —
    butun tizimni orqaga qaytaradigan amal, va uning xavfsizligi
    freymvork marshrutlash tafsilotiga bog'liq bo'lib qolmasligi kerak.
    """
    if not BACKUP_FILENAME_RE.match(filename or ""):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Noto'g'ri backup fayl nomi",
        )
    return filename


def get_backup_directory():
    """Backup papkasini olish"""
    project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    backup_dir = os.path.join(project_root, "database", "backups")
    os.makedirs(backup_dir, exist_ok=True)
    return backup_dir

def get_script_path(script_name: str):
    """Script yo'lini olish"""
    project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    return os.path.join(project_root, "scripts", script_name)

# ============================================================================
# Dashboard Statistics
# ============================================================================

@router.get("/dashboard/stats")
def get_dashboard_stats(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Dashboard uchun umumiy statistika"""
    check_admin_permission(current_user)
    
    # Users statistics
    total_users = db.query(func.count(User.id)).scalar()
    clients_count = db.query(func.count(User.id)).filter(User.role == "client").scalar()
    owners_count = db.query(func.count(User.id)).filter(User.role == "owner").scalar()
    
    # Equipment statistics
    total_equipment = db.query(func.count(Equipment.id)).scalar()
    available_equipment = db.query(func.count(Equipment.id)).filter(Equipment.available == True).scalar()
    
    # Orders statistics
    total_orders = db.query(func.count(Order.id)).scalar()
    pending_orders = db.query(func.count(Order.id)).filter(Order.status == "pending").scalar()
    confirmed_orders = db.query(func.count(Order.id)).filter(Order.status == "confirmed").scalar()
    completed_orders = db.query(func.count(Order.id)).filter(Order.status == "completed").scalar()
    
    # Balance statistics
    total_balance = db.query(func.sum(Balance.balance)).scalar() or 0
    total_transactions = db.query(func.count(BalanceTransaction.id)).scalar()
    
    # Recent activity (last 7 days)
    week_ago = datetime.utcnow() - timedelta(days=7)
    new_users_week = db.query(func.count(User.id)).filter(User.created_at >= week_ago).scalar()
    new_orders_week = db.query(func.count(Order.id)).filter(Order.created_at >= week_ago).scalar()
    
    return {
        "users": {
            "total": total_users,
            "clients": clients_count,
            "owners": owners_count,
            "new_this_week": new_users_week
        },
        "equipment": {
            "total": total_equipment,
            "available": available_equipment,
            "busy": total_equipment - available_equipment
        },
        "orders": {
            "total": total_orders,
            "pending": pending_orders,
            "confirmed": confirmed_orders,
            "completed": completed_orders,
            "new_this_week": new_orders_week
        },
        "balance": {
            "total_balance": float(total_balance),
            "total_transactions": total_transactions
        }
    }

# ============================================================================
# Users Management
# ============================================================================

@router.get("/users", response_model=List[UserRead])
def get_all_users(
    skip: int = 0,
    limit: int = 100,
    role: str = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Barcha foydalanuvchilarni olish"""
    check_admin_permission(current_user)
    
    query = db.query(User)
    
    if role:
        query = query.filter(User.role == role)
    
    users = query.offset(skip).limit(limit).all()
    return users

@router.delete("/users/{user_id}")
def delete_user(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Foydalanuvchini o'chirish"""
    check_admin_permission(current_user)
    
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    if user.role == "admin":
        raise HTTPException(status_code=400, detail="Cannot delete admin user")
    
    db.delete(user)
    db.commit()
    
    return {"message": "User deleted successfully"}

# ============================================================================
# Database Backup & Restore
# ============================================================================

@router.post("/backup/create")
def create_backup(
    backup_type: str = "full",
    current_user: User = Depends(get_current_user)
):
    """Database backup yaratish"""
    check_admin_permission(current_user)

    try:
        script_path = get_script_path("backup.sh")

        # Run backup script
        result = subprocess.run(
            [script_path, f"--{backup_type}"],
            capture_output=True,
            text=True,
            timeout=300  # 5 minutes timeout
        )

        if result.returncode == 0:
            return {
                "success": True,
                "message": "Backup created successfully",
                "output": result.stdout
            }
        else:
            raise HTTPException(
                status_code=500,
                detail=f"Backup failed: {result.stderr}"
            )
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=500, detail="Backup timeout")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/backup/list")
def list_backups(
    current_user: User = Depends(get_current_user)
):
    """Barcha backuplarni ko'rish"""
    check_admin_permission(current_user)

    backup_dir = get_backup_directory()
    backups = []

    try:
        for filename in os.listdir(backup_dir):
            if filename.startswith("backup_") and (filename.endswith(".sql") or filename.endswith(".sql.gz")):
                filepath = os.path.join(backup_dir, filename)
                stat = os.stat(filepath)

                # Read metadata if exists
                metadata_file = filepath + ".meta"
                metadata = {}
                if os.path.exists(metadata_file):
                    with open(metadata_file, 'r') as f:
                        metadata = json.load(f)

                backups.append({
                    "filename": filename,
                    "size": stat.st_size,
                    "size_human": f"{stat.st_size / (1024*1024):.2f} MB",
                    "created_at": datetime.fromtimestamp(stat.st_mtime).isoformat(),
                    "metadata": metadata
                })

        # Sort by creation time (newest first)
        backups.sort(key=lambda x: x["created_at"], reverse=True)

        return {
            "backups": backups,
            "total": len(backups)
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/backup/restore/{filename}")
def restore_backup(
    filename: str,
    current_user: User = Depends(get_current_user)
):
    """Backupdan restore qilish"""
    check_admin_permission(current_user)

    backup_dir = get_backup_directory()
    backup_file = os.path.join(backup_dir, safe_backup_filename(filename))

    if not os.path.exists(backup_file):
        raise HTTPException(status_code=404, detail="Backup file not found")

    try:
        script_path = get_script_path("restore.sh")

        # Run restore script with auto-confirmation
        process = subprocess.Popen(
            [script_path, backup_file],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        # Auto-confirm restore
        stdout, stderr = process.communicate(input="yes\n", timeout=300)

        if process.returncode == 0:
            return {
                "success": True,
                "message": "Database restored successfully",
                "output": stdout
            }
        else:
            raise HTTPException(
                status_code=500,
                detail=f"Restore failed: {stderr}"
            )
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=500, detail="Restore timeout")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.delete("/backup/delete/{filename}")
def delete_backup(
    filename: str,
    current_user: User = Depends(get_current_user)
):
    """Backupni o'chirish"""
    check_admin_permission(current_user)

    backup_dir = get_backup_directory()
    backup_file = os.path.join(backup_dir, safe_backup_filename(filename))

    if not os.path.exists(backup_file):
        raise HTTPException(status_code=404, detail="Backup file not found")

    try:
        # Delete backup file
        os.remove(backup_file)

        # Delete metadata file if exists
        metadata_file = backup_file + ".meta"
        if os.path.exists(metadata_file):
            os.remove(metadata_file)

        return {
            "success": True,
            "message": "Backup deleted successfully"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ============================================================================
# System Information
# ============================================================================

@router.get("/system/info")
def get_system_info(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Tizim haqida ma'lumot"""
    check_admin_permission(current_user)

    try:
        # Database size
        result = db.execute(text("""
            SELECT pg_size_pretty(pg_database_size(current_database())) as size
        """))
        db_size = result.fetchone()[0]

        # Table sizes
        result = db.execute(text("""
            SELECT
                schemaname,
                tablename,
                pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
            FROM pg_tables
            WHERE schemaname = 'public'
            ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
            LIMIT 10
        """))
        tables = [{"schema": row[0], "table": row[1], "size": row[2]} for row in result.fetchall()]

        return {
            "database_size": db_size,
            "tables": tables,
            "backup_directory": get_backup_directory()
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

