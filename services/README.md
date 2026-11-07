# services/

Reserved for independently managed systemd units:

- `user/`   → `~/.config/systemd/user/`
- `system/` → `/etc/systemd/system/`

**`install.sh` does not deploy, enable, or start anything here.** Each service is
an explicit future opt-in. See [the services design note](../docs/DESIGN.md#services)
for the requirements that apply before a unit is added.
