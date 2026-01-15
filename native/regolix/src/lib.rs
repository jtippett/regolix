use regorus::Engine;
use rustler::{Atom, ResourceArc};
use std::sync::RwLock;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        undefined,
        parse_error,
        eval_error,
        json_error,
        engine_error,
    }
}

pub struct EngineResource {
    engine: RwLock<Engine>,
}

#[rustler::resource_impl]
impl rustler::Resource for EngineResource {}

#[rustler::nif]
fn native_new() -> ResourceArc<EngineResource> {
    ResourceArc::new(EngineResource {
        engine: RwLock::new(Engine::new()),
    })
}

#[rustler::nif]
fn native_add_policy(
    resource: ResourceArc<EngineResource>,
    name: String,
    source: String,
) -> Result<(), (Atom, String)> {
    let mut engine = resource
        .engine
        .write()
        .map_err(|e| (atoms::engine_error(), e.to_string()))?;

    engine
        .add_policy(name, source)
        .map(|_| ())
        .map_err(|e| (atoms::parse_error(), e.to_string()))
}

#[rustler::nif]
fn native_set_input(
    resource: ResourceArc<EngineResource>,
    json_input: String,
) -> Result<(), (Atom, String)> {
    let mut engine = resource
        .engine
        .write()
        .map_err(|e| (atoms::engine_error(), e.to_string()))?;

    let value: regorus::Value = regorus::Value::from_json_str(&json_input)
        .map_err(|e| (atoms::json_error(), e.to_string()))?;

    engine
        .set_input(value);

    Ok(())
}

#[rustler::nif]
fn native_get_packages(
    resource: ResourceArc<EngineResource>,
) -> Result<Vec<String>, (Atom, String)> {
    let engine = resource
        .engine
        .read()
        .map_err(|e| (atoms::engine_error(), e.to_string()))?;

    engine
        .get_packages()
        .map_err(|e| (atoms::engine_error(), e.to_string()))
}

rustler::init!("Elixir.Regolix.Native", [native_new, native_add_policy, native_set_input, native_get_packages]);
