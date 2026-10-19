use std::{collections::HashMap, sync::Arc};

use rmpv::Value;

use super::{HighlightRole, Style};

/// A complete, route-local snapshot. Parse before replacing a live registry.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct HighlightRoles {
    groups: HashMap<String, Vec<HighlightRole>>,
}

impl HighlightRoles {
    pub fn parse(arguments: &[Value]) -> Result<Self, String> {
        let [snapshot] = arguments else { return Err("Expected one role snapshot".into()) };
        let entries = snapshot.as_map().ok_or("Role snapshot must be a map")?;
        if entries.len() != 2 {
            return Err("Role snapshot needs version and groups".into());
        }
        let field =
            |key: &str| entries.iter().find_map(|(k, v)| (k.as_str() == Some(key)).then_some(v));
        if field("version").and_then(Value::as_u64) != Some(1) {
            return Err("Unsupported highlight role version".into());
        }
        let groups = field("groups")
            .and_then(Value::as_map)
            .filter(|groups| groups.len() <= 256)
            .ok_or("Expected at most 256 role groups")?;
        let mut parsed = Self::default();
        for (name, roles) in groups {
            let name = name
                .as_str()
                .filter(|name| !name.is_empty() && name.len() <= 128)
                .ok_or("Invalid highlight group name")?;
            let roles = roles
                .as_array()
                .filter(|roles| roles.len() <= 4)
                .ok_or("Expected at most four roles per group")?;
            let mut parsed_roles = Vec::new();
            for role in roles {
                let role = match role.as_str() {
                    Some("enlarged_icon") => HighlightRole::EnlargedIcon,
                    Some("notebook_kernel") => HighlightRole::NotebookKernel,
                    Some("notebook_actions") => HighlightRole::NotebookActions,
                    Some("solid_title_cap") => HighlightRole::SolidTitleCap,
                    Some("reference_outline") => HighlightRole::ReferenceOutline,
                    _ => return Err("Unknown highlight rendering role".into()),
                };
                if parsed_roles.contains(&role) {
                    return Err("Duplicate highlight rendering role".into());
                }
                parsed_roles.push(role);
            }
            if parsed_roles.contains(&HighlightRole::NotebookKernel)
                && parsed_roles.contains(&HighlightRole::NotebookActions)
            {
                return Err("Conflicting Notebook title roles".into());
            }
            if parsed.groups.insert(name.to_owned(), parsed_roles).is_some() {
                return Err("Duplicate highlight group".into());
            }
        }
        Ok(parsed)
    }

    pub fn apply(&self, style: Style, names: &[String]) -> Style {
        // Nvim lists the UI base before the explicit syntax group. Retain all
        // names and let the later, more specific title role win.
        style.with_roles(names.iter().filter_map(|name| self.groups.get(name)).flatten().copied())
    }

    pub fn rebuild(
        &self,
        names: &HashMap<u64, Vec<String>>,
        styles: &mut HashMap<u64, Arc<Style>>,
    ) -> HashMap<usize, Arc<Style>> {
        let mut replacements = HashMap::new();
        for (id, style) in styles {
            let updated = self.apply((**style).clone(), names.get(id).map_or(&[], Vec::as_slice));
            if **style != updated {
                let updated = Arc::new(updated);
                replacements.insert(Arc::as_ptr(style) as usize, updated.clone());
                *style = updated;
            }
        }
        replacements
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::editor::{Colors, NotebookTitleGroup};

    fn packet(groups: Vec<(&str, Vec<&str>)>) -> Vec<Value> {
        vec![Value::Map(vec![
            ("version".into(), 1.into()),
            (
                "groups".into(),
                Value::Map(
                    groups
                        .into_iter()
                        .map(|(name, roles)| {
                            (
                                name.into(),
                                Value::Array(roles.into_iter().map(Value::from).collect()),
                            )
                        })
                        .collect(),
                ),
            ),
        ])]
    }

    #[test]
    fn arbitrary_composite_names_rebuild_and_clear_without_crossing_routes() {
        let registry = HighlightRoles::parse(&packet(vec![
            ("MyBase", vec!["solid_title_cap", "reference_outline"]),
            ("MyRenamedSyntax", vec!["enlarged_icon", "notebook_actions"]),
        ]))
        .unwrap();
        let names = HashMap::from([(7, vec!["MyBase".into(), "MyRenamedSyntax".into()])]);
        let plain = Arc::new(Style::new(Colors::new(None, None, None)));
        let mut styles = HashMap::from([(7, plain.clone())]);
        let replacements = registry.rebuild(&names, &mut styles);
        assert_eq!(replacements.len(), 1);
        assert!(
            styles[&7].enlarged_icon && styles[&7].avante_solid_cap && styles[&7].reference_outline
        );
        assert_eq!(styles[&7].notebook_title, Some(NotebookTitleGroup::Actions));
        assert_eq!(HighlightRoles::default().apply((*plain).clone(), &names[&7]), *plain);
        let clear = HighlightRoles::parse(&packet(vec![])).unwrap();
        assert_eq!(clear.rebuild(&names, &mut styles).len(), 1);
        assert_eq!(styles[&7], plain);
    }

    #[test]
    fn invalid_snapshots_are_rejected_before_live_registry_replacement() {
        for groups in [
            vec![("x", vec!["unknown"])],
            vec![("", vec![])],
            vec![("x", vec!["notebook_kernel", "notebook_actions"])],
            vec![("x", vec!["enlarged_icon", "enlarged_icon"])],
            vec![("x", vec![]), ("x", vec![])],
        ] {
            assert!(HighlightRoles::parse(&packet(groups)).is_err());
        }
        assert!(HighlightRoles::parse(&[]).is_err());
        assert!(
            HighlightRoles::parse(&[Value::Map(vec![
                ("version".into(), 2.into()),
                ("groups".into(), Value::Map(vec![]))
            ])])
            .is_err()
        );
    }
}
