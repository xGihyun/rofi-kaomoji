use anyhow::Context;
use serde::{Deserialize, Serialize};
use std::{
    env,
    fs::File,
    io::{Read, Write},
    process::{Command, Stdio},
};

#[derive(Debug, Deserialize, Serialize)]
struct Kaomoji {
    value: String,
    description: String,
}

fn main() -> Result<(), anyhow::Error> {
    let current_path = env::var("HOME")?;

    println!("{}", current_path);
    let ron_path = format!("{}/dotfiles-hyprland/kaomoji.ron", current_path);
    let mut file = File::open(ron_path).context("Failed to open kaomoji.ron")?;
    let mut contents = String::new();

    file.read_to_string(&mut contents)?;

    let kaomojis: Vec<Kaomoji> = ron::from_str(&contents)?;
    let string_list: String = kaomojis
        .iter()
        .map(|kaomoji| format!("{} {}", kaomoji.value, kaomoji.description))
        .collect::<Vec<String>>()
        .join("\n");

    println!("{string_list:?}");

    let app_launcher = Command::new("rofi")
        .args(["-format", "i", "-dmenu", "-i"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()?;

    app_launcher
        .stdin
        .unwrap()
        .write_all(&string_list.as_bytes())?;

    let mut kaomoji_index = String::new();
    app_launcher
        .stdout
        .unwrap()
        .read_to_string(&mut kaomoji_index)?;

    let index: usize = kaomoji_index.trim().parse()?;

    let selected = &kaomojis[index].value;

    println!("{}", kaomoji_index);
    println!("{}", selected);

    Command::new("wl-copy").arg(selected.trim()).spawn()?;

    Ok(())
}
