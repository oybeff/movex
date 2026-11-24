"""Admin P5 (Figma «Admin panel» 00, 01, 08, 09): rollar, 2FA, taklif, push, GPS.

- users.admin_role — besh rol (super_admin, operator, finance, moderator,
  support). Mavjud adminlar — super_admin: ular bugun ham hamma narsani
  qila oladi, migratsiya hech kimni panelsiz qoldirmasin.
- users.admin_disabled_at — «Ishdan ketgan»: kira olmaydi, tarix qoladi.
- users.last_seen_at / app_version / app_platform / app_flavor — ilova har
  so'rovda yuboradi (X-App-*). Push auditoriyasi (oxirgi faollik) va
  «eski versiyada» ustuni shundan; taxminiy raqam yo'q.
- admin_login_attempts — 5 xato / 15 daqiqa blok va audit uchun.
- admin_otp — SMS kod (2FA va parolni tiklash), xeshlangan.
- admin_trusted_devices — «Qurilmani 30 kun eslab qolish».
- admin_invites — taklif havolasi, 48 soat.
- admin_actions.ip / user_agent — S10 tafsiloti.
- push_campaigns + notifications.campaign_id — yetkazildi/ochildi
  hisoblanadi, saqlanmaydi.
- driver_locations — jonli xarita: haydovchi ilovasi har 10 s yuboradi.

Revision ID: d9f2b4c6e813
Revises: c6a8e0b2d417
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

revision = 'd9f2b4c6e813'
down_revision = 'c6a8e0b2d417'
branch_labels = None
depends_on = None

ROLES = "('super_admin','operator','finance','moderator','support')"


def upgrade():
    op.add_column('users', sa.Column('admin_role', sa.String(20), nullable=True))
    op.add_column('users', sa.Column('admin_disabled_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('last_seen_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('app_version', sa.String(20), nullable=True))
    op.add_column('users', sa.Column('app_platform', sa.String(10), nullable=True))
    op.add_column('users', sa.Column('app_flavor', sa.String(10), nullable=True))
    op.create_check_constraint('check_user_admin_role', 'users',
                               f"admin_role IS NULL OR admin_role IN {ROLES}")
    op.execute("UPDATE users SET admin_role = 'super_admin' WHERE role = 'admin'")

    op.create_table(
        'admin_login_attempts',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('login', sa.String(50), nullable=False, index=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=True),
        sa.Column('stage', sa.String(10), nullable=False),
        sa.Column('success', sa.Boolean(), nullable=False),
        sa.Column('ip', sa.String(64), nullable=True),
        sa.Column('user_agent', sa.String(300), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False,
                  index=True),
        sa.CheckConstraint("stage IN ('password','sms','reset')", name='check_admin_login_stage'),
    )
    op.create_table(
        'admin_otp',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False,
                  index=True),
        sa.Column('purpose', sa.String(10), nullable=False),
        sa.Column('code_hash', sa.String(255), nullable=False),
        sa.Column('attempts', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('used_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("purpose IN ('login','reset')", name='check_admin_otp_purpose'),
    )
    op.create_table(
        'admin_trusted_devices',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False,
                  index=True),
        sa.Column('token_hash', sa.String(64), nullable=False, unique=True),
        sa.Column('user_agent', sa.String(300), nullable=True),
        sa.Column('ip', sa.String(64), nullable=True),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_table(
        'admin_invites',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('token_hash', sa.String(64), nullable=False, unique=True),
        sa.Column('phone', sa.String(20), nullable=False),
        sa.Column('full_name', sa.String(120), nullable=False),
        sa.Column('admin_role', sa.String(20), nullable=False),
        sa.Column('invited_by', sa.Integer(), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('accepted_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('revoked_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint(f"admin_role IN {ROLES}", name='check_admin_invite_role'),
    )
    op.add_column('admin_actions', sa.Column('ip', sa.String(64), nullable=True))
    op.add_column('admin_actions', sa.Column('user_agent', sa.String(300), nullable=True))

    op.create_table(
        'push_campaigns',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('title_uz', sa.String(120), nullable=False),
        sa.Column('body_uz', sa.Text(), nullable=False),
        sa.Column('title_ru', sa.String(120), nullable=True),
        sa.Column('body_ru', sa.Text(), nullable=True),
        sa.Column('audience', JSONB(), nullable=False),
        sa.Column('status', sa.String(12), nullable=False, server_default='draft'),
        sa.Column('scheduled_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('sent_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('recipients', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('pushed', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('error', sa.Text(), nullable=True),
        sa.Column('created_by', sa.Integer(), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("status IN ('draft','scheduled','sending','sent','failed','cancelled')",
                           name='check_push_campaign_status'),
    )
    op.add_column('notifications', sa.Column('campaign_id', sa.Integer(),
                                             sa.ForeignKey('push_campaigns.id', ondelete='SET NULL'),
                                             nullable=True))
    op.create_index('ix_notifications_campaign', 'notifications', ['campaign_id'])

    op.create_table(
        'driver_locations',
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), primary_key=True),
        sa.Column('online', sa.Boolean(), nullable=False, server_default=sa.text('false')),
        sa.Column('latitude', sa.Numeric(10, 7), nullable=True),
        sa.Column('longitude', sa.Numeric(10, 7), nullable=True),
        sa.Column('accuracy_m', sa.Numeric(8, 1), nullable=True),
        sa.Column('speed_kmh', sa.Numeric(6, 1), nullable=True),
        sa.Column('heading', sa.Numeric(5, 1), nullable=True),
        sa.Column('location_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )


def downgrade():
    op.drop_table('driver_locations')
    op.drop_index('ix_notifications_campaign', 'notifications')
    op.drop_column('notifications', 'campaign_id')
    op.drop_table('push_campaigns')
    op.drop_column('admin_actions', 'user_agent')
    op.drop_column('admin_actions', 'ip')
    op.drop_table('admin_invites')
    op.drop_table('admin_trusted_devices')
    op.drop_table('admin_otp')
    op.drop_table('admin_login_attempts')
    op.drop_constraint('check_user_admin_role', 'users', type_='check')
    for c in ('app_flavor', 'app_platform', 'app_version', 'last_seen_at', 'admin_disabled_at', 'admin_role'):
        op.drop_column('users', c)
