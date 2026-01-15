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

rustler::init!("Elixir.Regolix.Native", [native_new, native_add_policy]);
