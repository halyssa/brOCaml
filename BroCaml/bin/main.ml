open BroCaml.Data
open BroCaml.User
open BroCaml.Login
open Lwt
open Cohttp_lwt_unix
open Sqlite3
open BroCaml.Rating

let current_user = ref ""
let is_guest : bool ref = ref false
let public_db_file = "findmyfood.db"
let personal_db_file = "personal_ratings.db"
let public_db = connect_db_checked public_db_file
let personal_db = connect_db_checked personal_db_file

let quit_program () =
  print_endline "Thanks for using FindMyFood!";
  exit 0

exception BindingError of string

let run_search_food food eateries =
  let result = search_food food eateries in
  if result = [] then
    Printf.printf "Unfortunately, %s is not served in the eateries today. " food
  else List.iter (fun p -> Printf.printf "%s\n" p) result

let run_contains food eateries =
  let result = contains food eateries in
  match result with
  | true ->
      Printf.printf
        "%s is served in the eateries today!\n\
        \   Would you like to see where it is  served (y/n)? " food;
      let response = read_line () in
      if response = "y" then run_search_food food eateries
  | false ->
      Printf.printf "Unfortunately, %s is not served in the eateries today. "
        food

let rec prompt_user_find public_db personal_db eateries =
  print_endline "\n Which number best fits your desired action? ";
  print_endline
    "1. Check if <food> is served at any of the eateries (ex. 1 pizza)";
  print_endline "2. Search where <food> is being served (ex. 2 pizza)";
  print_endline "3. Quit";
  let action = read_line () in
  let parts = String.split_on_char ' ' action in
  match parts with
  | [ "1"; food ] ->
      run_contains food eateries;
      prompt_user_find public_db personal_db eateries
  | [ "2"; food ] ->
      run_search_food food eateries;
      prompt_user_find public_db personal_db eateries
  | [ "3" ] -> Lwt.return (quit_program ())
  | _ ->
      print_endline "That action does not exist or is incorrectly formatted.";
      prompt_user_find public_db personal_db eateries

let rec prompt_user_sort_3 db eateries =
  print_endline
    "\n Select a sorting option: (default is ascending chronological)";
  print_endline "1. Sort by highest rating";
  print_endline "2. Sort by lowest rating";
  print_endline "3. Sort eateries alphabetically (A-Z)";
  print_endline "4. Sort eateries reverse alphabetically (Z-A)";
  print_endline "5. Sort food items alphabetically (A-Z)";
  print_endline "6. Sort food items reverse alphabetically (Z-A)";
  print_endline "7. Sort chronologically (oldest first)";
  print_endline "8. Sort reverse chronologically (newest first)";
  print_endline "9. Go back";

  let choice = read_line () in
  let table = "Ratings" in
  match choice with
  | "" ->
      let user = !current_user in
      let%lwt () = show_personal_ratings db user is_guest in
      prompt_user_sort_3 db eateries
  | "1" ->
      let%lwt () = sort_by_highest_rating db table in
      prompt_user_sort_3 db eateries
  | "2" ->
      let%lwt () = sort_by_lowest_rating db table in
      prompt_user_sort_3 db eateries
  | "3" ->
      let%lwt () = sort_by_eatery_alphabetical db table in
      prompt_user_sort_3 db eateries
  | "4" ->
      let%lwt () = sort_by_eatery_reverse_alphabetical db table in
      prompt_user_sort_3 db eateries
  | "5" ->
      let%lwt () = sort_by_food_alphabetical db table in
      prompt_user_sort_3 db eateries
  | "6" ->
      let%lwt () = sort_by_food_reverse_alphabetical db table in
      prompt_user_sort_3 db eateries
  | "7" ->
      let%lwt () = sort_by_date_asc db table in
      prompt_user_sort_3 db eateries
  | "8" ->
      let%lwt () = sort_by_date_desc db table in
      prompt_user_sort_3 db eateries
  | "9" -> Lwt.return ()
  | _ ->
      print_endline "Invalid choice. Please try again.";
      prompt_user_sort_3 db eateries

let rec prompt_user_sort_4 db food eateries =
  print_endline "\nSelect a sorting option: ";
  print_endline "1. Sort by highest rating";
  print_endline "2. Sort by lowest rating";
  print_endline "3. Sort eateries alphabetically (A-Z)";
  print_endline "4. Sort eateries reverse alphabetically (Z-A)";
  print_endline "5. Sort chronologically (oldest first)";
  print_endline "6. Sort reverse chronologically (newest first)";
  print_endline "7. Go back";
  let choice = read_line () in
  match choice with
  | "1" | "2" | "3" | "4" | "5" | "6" ->
      show_public_ratings db food choice;
      prompt_user_sort_4 db food eateries
  | "7" -> Lwt.return ()
  | _ ->
      print_endline "Invalid choice. Please try again.";
      prompt_user_sort_4 db food eateries

let rec prompt_user_rate public_db personal_db eateries =
  print_endline "\n Which number best fits your desired action? ";
  print_endline "1. Rate <food> offered by <eatery> (ex. 1 pizza 5 Okenshields)";
  print_endline
    "2. View the rating of <food> at <eatery> (ex. 2 pizza Okenshields)";

  print_endline "3. View your personal ratings";
  print_endline "4. Show all ratings for <food> (ex. 4 pizza)";
  print_endline "5. Quit";
  let eatery = ref "" in
  let action = read_line () in
  let parts = String.split_on_char ' ' action in
  match parts with
  | "1" :: food :: rating :: eatery_name -> (
      try
        (if eatery_name <> [] then
           let eat = String.concat " " eatery_name in
           eatery := eat);

        let rating = int_of_string rating in
        if rating < 1 || rating > 5 then (
          print_endline "Rating must be between 1 and 5.";
          prompt_user_rate public_db personal_db eateries)
        else (
          print_endline
            "Would you like to submit this rating anonymously? (y/n)";
          match read_line () with
          | "y" ->
              let%lwt () =
                let user = !current_user in
                rate_food public_db personal_db food !eatery rating is_guest
                  user true eateries
              in
              prompt_user_rate public_db personal_db eateries
          | _ ->
              let user = !current_user in
              let%lwt () =
                rate_food public_db personal_db food !eatery rating is_guest
                  user false eateries
              in
              prompt_user_rate public_db personal_db eateries)
      with Failure _ ->
        print_endline "Invalid rating. Please enter a number between 1 and 5.";
        prompt_user_rate public_db personal_db eateries)
  | [ "2"; food; eatery ] ->
      let%lwt () = view_food_rating public_db food eatery eateries in
      prompt_user_rate public_db personal_db eateries
  | [ "3" ] ->
      let user = !current_user in
      let%lwt () = show_personal_ratings public_db user is_guest in
      prompt_user_rate public_db personal_db eateries
  | [ "4"; food ] ->
      let%lwt () = prompt_user_sort_4 public_db food eateries in
      prompt_user_rate public_db personal_db eateries
  | [ "5" ] -> Lwt.return (quit_program ())
  | _ ->
      print_endline "That action does not exist or is incorrectly formatted.";
      prompt_user_rate public_db personal_db eateries

let rec prompt_user public_db personal_db eateries =
  print_endline "\nPlease choose a number that best fits your desired action:";
  print_endline "1. Find foods";
  print_endline "2. Rate foods";
  print_endline "3. Quit";

  let action = read_line () in
  let parts = String.split_on_char ' ' action in
  match parts with
  | [ "1" ] -> prompt_user_find public_db personal_db eateries
  | [ "2" ] -> prompt_user_rate public_db personal_db eateries
  | [ "3" ] -> Lwt.return (quit_program ())
  | _ ->
      print_endline "That action does not exist or is incorrectly formatted.";
      prompt_user public_db personal_db eateries

let user_entered public_db personal_db =
  let%lwt eateries = get_data () in
  let%lwt () = prompt_user public_db personal_db eateries in
  Lwt.return_unit

let rec login_or_create_account db =
  print_endline "Welcome! Please choose an action:";
  print_endline "1. Log in";
  print_endline "2. Create an account";
  print_endline "3. Proceed as a guest";
  print_endline "4. Quit";
  let choice = read_line () in
  match choice with
  | "1" ->
      print_string "Enter username: ";
      let username = read_line () in
      print_string "Enter password: ";
      let password = read_line () in
      if%lwt validate_user db username password then (
        Printf.printf "Welcome back, %s!\n" username;
        current_user := username;
        Lwt.return_unit)
      else (
        print_endline "Invalid username or password. Please try again.\n";
        login_or_create_account db)
  | "2" ->
      print_string "Choose a username: ";
      let username = read_line () in
      let%lwt exists = Lwt.return (user_exists db username) in
      if exists then (
        print_endline "This username is already taken. Please choose another.\n";
        login_or_create_account db)
      else (
        print_string "Choose a password: ";
        let password = read_line () in
        let finalize_fn stmt db = ignore (Sqlite3.finalize stmt) in
        Lwt.ignore_result
          (create_user ~finalize:finalize_fn db username password;
           print_endline "Account created successfully!";
           current_user := username;
           Lwt.return_unit);
        Lwt.return_unit)
  | "3" ->
      print_endline "You are now proceeding as a guest.";
      is_guest := true;
      Lwt.return_unit
  | "4" -> quit_program ()
  | _ ->
      print_endline "Invalid choice. Please try again.\n";
      login_or_create_account db

let debug_list_tables db db_name =
  let query = "SELECT name FROM\n   sqlite_master WHERE type='table';" in
  let stmt = Sqlite3.prepare db query in
  Printf.printf "Listing tables in %s:\n" db_name;
  let rec fetch_tables () =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW ->
        let table_name = Sqlite3.column stmt 0 |> Sqlite3.Data.to_string in
        Printf.printf " - %s\n" (Option.value ~default:"UNKNOWN" table_name);
        fetch_tables ()
    | Sqlite3.Rc.DONE -> ()
    | _ -> print_endline "Error fetching tables."
  in
  fetch_tables ();
  Sqlite3.finalize stmt |> ignore

let () =
  Lwt_main.run
    (let%lwt () = login_or_create_account public_db in
     user_entered public_db personal_db);

  db_close public_db |> ignore;
  db_close personal_db |> ignore
