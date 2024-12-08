open User
open Cohttp_lwt_unix

(* type eatery = { name : string; menu : string list; } *)
(** type [eatery] stores a string [name] and string list [menu]*)

(** [fetch_json] is the json of [url]. Raises:
    - Fails with "HTTP request failed with error" if the HTTP request is
      unsuccessful.
    - Fails with "JSON parsing error" if the response body cannot be parsed as
      JSON.
    - Fails with "Unexpected error: <msg>" if an unexpected error occurs during
      the request or parsing.*)
let fetch_json url =
  try%lwt
    let%lwt response, body = Client.get (Uri.of_string url) in
    let%lwt body_string = Cohttp_lwt.Body.to_string body in
    let json = Yojson.Safe.from_string body_string in
    (* print_endline "Successfully fetched and parsed JSON."; *)
    Lwt.return json
  with
  | Failure _ -> Lwt.fail_with "HTTP request failed with error"
  | Yojson.Json_error e -> Lwt.fail_with "JSON parsing error"
  | e ->
      Lwt.fail_with
        (Printf.sprintf "Unexpected error: %s" (Printexc.to_string e))

(** [parse_eateries] parses the given JSON object [json] and returns an Lwt list
    of eateries. *)
let parse_eateries (json : Yojson.Safe.t) : User.eatery list Lwt.t =
  try
    match
      json
      |> Yojson.Safe.Util.member "data"
      |> Yojson.Safe.Util.member "eateries"
    with
    | `Null -> Lwt.return [] (* Return an empty list if "eateries" is null *)
    | eateries_json ->
        let eateries =
          eateries_json |> Yojson.Safe.Util.to_list
          |> List.map (fun eatery ->
                 let name =
                   eatery
                   |> Yojson.Safe.Util.member "name"
                   |> Yojson.Safe.Util.to_string
                 in
                 let menu_items =
                   let dining_items =
                     match eatery |> Yojson.Safe.Util.member "diningItems" with
                     | `Null -> []
                     | items_json ->
                         items_json |> Yojson.Safe.Util.to_list
                         |> List.map (fun item ->
                                item
                                |> Yojson.Safe.Util.member "item"
                                |> Yojson.Safe.Util.to_string)
                   in
                   let operating_hours =
                     match
                       eatery |> Yojson.Safe.Util.member "operatingHours"
                     with
                     | `Null -> []
                     | hours_json -> hours_json |> Yojson.Safe.Util.to_list
                   in
                   let menu_from_events =
                     operating_hours
                     |> List.fold_left
                          (fun acc hour ->
                            match hour |> Yojson.Safe.Util.member "events" with
                            | `Null -> acc
                            | events_json ->
                                let events_list =
                                  events_json |> Yojson.Safe.Util.to_list
                                in
                                acc
                                @ (events_list
                                  |> List.fold_left
                                       (fun acc event ->
                                         match
                                           event
                                           |> Yojson.Safe.Util.member "menu"
                                         with
                                         | `Null -> acc
                                         | menu_json ->
                                             let menu_list =
                                               menu_json
                                               |> Yojson.Safe.Util.to_list
                                             in
                                             acc
                                             @ (menu_list
                                               |> List.fold_left
                                                    (fun acc category ->
                                                      match
                                                        category
                                                        |> Yojson.Safe.Util
                                                           .member "items"
                                                      with
                                                      | `Null -> acc
                                                      | items_json ->
                                                          let items_list =
                                                            items_json
                                                            |> Yojson.Safe.Util
                                                               .to_list
                                                          in
                                                          acc
                                                          @ (items_list
                                                            |> List.map
                                                                 (fun item ->
                                                                   item
                                                                   |> Yojson
                                                                      .Safe
                                                                      .Util
                                                                      .member
                                                                        "item"
                                                                   |> Yojson
                                                                      .Safe
                                                                      .Util
                                                                      .to_string)
                                                            ))
                                                    []))
                                       []))
                          []
                   in
                   if List.length menu_from_events > 0 then menu_from_events
                   else if List.length dining_items > 0 then dining_items
                   else
                     match
                       eatery |> Yojson.Safe.Util.member "diningCuisines"
                     with
                     | `Null -> []
                     | cuisines_json ->
                         cuisines_json |> Yojson.Safe.Util.to_list
                         |> List.map (fun cuisine ->
                                cuisine
                                |> Yojson.Safe.Util.member "name"
                                |> Yojson.Safe.Util.to_string)
                 in
                 User.create_eatery name menu_items)
        in
        Lwt.return eateries
  with e ->
    print_endline ("Unexpected error in parse_eateries: " ^ Printexc.to_string e);
    Lwt.return []

(** [get_data] returns a Lwt list of eateries from
    "https://now.dining.cornell.edu/api/1.0/dining/eateries.json" *)
let get_data () : User.eatery list Lwt.t =
  let url = "https://now.dining.cornell.edu/api/1.0/dining/eateries.json" in
  try%lwt
    let%lwt json = fetch_json url in
    let%lwt eateries = parse_eateries json in
    Lwt.return eateries
  with
  | Failure msg when msg = "HTTP request failed with error" ->
      print_endline "Error: Could not fetch data from the dining API.";
      Lwt.return []
  | Failure msg when msg = "JSON parsing error" ->
      print_endline
        "Error: Failed to parse the JSON response from the dining API.";
      Lwt.return []
  | Failure msg ->
      print_endline (Printf.sprintf "Unexpected error in get_data: %s" msg);
      Lwt.return []
