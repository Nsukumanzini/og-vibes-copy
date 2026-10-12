export type AdminAccessRole = "owner" | "vice_admin";

const ownerOnlyActions = new Set([
  "set_vice_admin",
  "audit_export",
  "remove",
  "set_feature_flag",
  "system_health",
]);

export function canPerformAdminAction(role: AdminAccessRole, action: string) {
  return role === "owner" || !ownerOnlyActions.has(action);
}

export function canChangeProfileRole(role: AdminAccessRole, actorId: string, targetId: string) {
  return role === "owner" && Boolean(targetId) && actorId !== targetId;
}

export function isProtectedAdminTarget(hasAdminMembership: boolean) {
  return hasAdminMembership;
}
