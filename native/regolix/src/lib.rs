use regorus::Engine;
use rustler::{Atom, Env, ResourceArc, Term};
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

rustler::init!("Elixir.Regolix.Native", [native_new]);
